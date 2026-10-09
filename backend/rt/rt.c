// EXPERIMENTAL runtime for the C output of backend/; see rt.h.
// GC, startup, exceptions, boxes, arrays.
#define _GNU_SOURCE // madvise (cosmocc)
#include "rt.h"
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <sys/mman.h>
#include <unistd.h>

#ifdef __TINYC__ // tcc, for fast development builds: no bit-scan builtin
static inline int __builtin_ctzll(uint64_t m) {
	int i = 0;
	while (!(m & 1)) {
		m >>= 1;
		i++;
	}
	return i;
}
#endif

char *rt_young_start, *rt_young_ptr, *rt_young_limit;
static char *old_start, *old_ptr, *old_end;
void **rt_sp;
void **rt_stack_base; // the running thread's shadow stack (rt_thread.c swaps it)
void **rt_globals;
static int nglobals;
rt_handler *rt_hcur;
void *rt_exn;
static void ***remembered;
static size_t remembered_len, remembered_cap;
static size_t minor_size;
static int stats;
static int release_pages;
static void populate(char *upto);
static unsigned long minors, majors;
static double minor_secs, major_secs; // RT_STATS
#include <time.h>
static double now_secs(void) {
	struct timespec t;
	clock_gettime(CLOCK_MONOTONIC, &t);
	return t.tv_sec + t.tv_nsec * 1e-9;
}
int rt_argc;
char **rt_argv;

static inline uint32_t obj_bytes(void *o) { return 8 * (NSLOTS(o) + 1); }

static char *copy_to(char *dst, void *obj) {
	uint32_t words = NSLOTS(obj) + 1;
	uint64_t *s = (uint64_t *)obj - 1, *d = (uint64_t *)dst;
	if (words <= 8) // most objects: a few words, no call
		for (uint32_t i = 0; i < words; i++)
			d[i] = s[i];
	else
		memcpy(dst, s, 8 * (size_t)words);
	return dst + 8;
}

static inline int in_young(void *p) {
	return (char *)p >= rt_young_start && (char *)p < rt_young_limit;
}

static inline void forward_to(void *p, void *n) {
	HDR(p) = (HDR(p) & ~((uint64_t)0xF << 28)) | ((uint64_t)K_FWD << 28);
	FP(p, 0) = n;
}

// ---- minor collection: copy live nursery objects to the end of the old space

static void *minor_forward(void *p) {
	if (!in_young(p)) return p;
	if (KIND(p) == K_FWD) return FP(p, 0);
	void *n = copy_to(old_ptr, p);
	old_ptr += obj_bytes(p);
	forward_to(p, n);
	return n;
}

static void scan_object(void *o, void *(*fwd)(void *)) {
	uint32_t n = NSLOTS(o);
	switch (KIND(o)) {
	case K_OBJ: {
		const uint64_t *pm = rt_types[TINDEX(o)].ptrmap;
		if (!pm) break;
		for (uint32_t w = 0; w * 64 < n; w++) {
			uint64_t m = pm[w];
			while (m) {
				int i = w * 64 + __builtin_ctzll(m);
				m &= m - 1;
				if (FP(o, i)) FP(o, i) = fwd(FP(o, i));
			}
		}
		break;
	}
	case K_PARR:
		for (uint32_t i = 0; i < n; i++)
			if (FP(o, i)) FP(o, i) = fwd(FP(o, i));
		break;
	default: break;
	}
}

static void scan_roots(void *(*fwd)(void *)) {
	for (void **s = rt_stack_base; s < rt_sp; s++)
		if (*s) *s = fwd(*s);
	rt_threads_scan(fwd); // the other green threads' shadow stacks
	for (int i = 0; i < nglobals; i++)
		if (rt_globals[i]) rt_globals[i] = fwd(rt_globals[i]);
	if (rt_exn) rt_exn = fwd(rt_exn);
}

// Depth-first copying: an object's descendants are copied right after it
// (preorder), the order in which the compiler then walks its trees; Cheney's
// breadth-first scan scatters them. RT_BFS=1 selects the breadth-first scan.
typedef struct {
	void *o;
	uint32_t i; // next slot to scan
} gc_frame;
static gc_frame *gc_stack;
static size_t gc_top, gc_cap;
static int gc_bfs;
static void *(*gc_fwd)(void *);

static void gc_push(void *o) {
	if (gc_top == gc_cap) {
		gc_cap = gc_cap ? gc_cap * 2 : 4096;
		gc_stack = (gc_frame *)realloc(gc_stack, gc_cap * sizeof(gc_frame));
	}
	gc_stack[gc_top].o = o;
	gc_stack[gc_top].i = 0;
	gc_top++;
}

static void gc_drain(void) {
	while (gc_top) {
		gc_frame *f = &gc_stack[gc_top - 1];
		void *o = f->o;
		uint32_t n = NSLOTS(o), k = KIND(o);
		const uint64_t *pm = k == K_OBJ ? rt_types[TINDEX(o)].ptrmap : 0;
		if (k == K_RAW || (k == K_OBJ && !pm)) {
			gc_top--;
			continue;
		}
		uint32_t i = f->i;
		for (; i < n; i++) {
			if (pm && !((pm[i >> 6] >> (i & 63)) & 1)) continue;
			void *v = FP(o, i);
			if (!v) continue;
			char *before = old_ptr;
			void *nv = gc_fwd(v);
			FP(o, i) = nv;
			if (old_ptr != before) { // copied just now: its subtree next
				f->i = i + 1;
				gc_push(nv); // may move gc_stack: f is not used after this
				goto next;
			}
		}
		gc_top--;
	next:;
	}
}

// forward a root, then copy everything reachable from it that is still to copy
static void *fwd_root(void *p) {
	char *before = old_ptr;
	void *n = gc_fwd(p);
	if (old_ptr != before) {
		gc_push(n);
		gc_drain();
	}
	return n;
}

static void major(size_t need);

static void minor_(void);
static void minor(void) {
	double t0 = stats ? now_secs() : 0;
	unsigned long m0 = majors;
	minor_();
	if (stats && majors == m0) minor_secs += now_secs() - t0;
}

static void minor_(void) {
	size_t young_used = rt_young_ptr - rt_young_start;
	if ((size_t)(old_end - old_ptr) < young_used + 64) {
		major(0);
		return;
	}
	minors++;
	populate(old_ptr + young_used);
	char *scan = old_ptr;
	if (!gc_bfs) {
		gc_fwd = minor_forward;
		scan_roots(fwd_root);
		for (size_t i = 0; i < remembered_len; i++)
			if (*remembered[i]) *remembered[i] = fwd_root(*remembered[i]);
		remembered_len = 0;
		rt_young_ptr = rt_young_start;
		return;
	}
	scan_roots(minor_forward);
	for (size_t i = 0; i < remembered_len; i++)
		if (*remembered[i]) *remembered[i] = minor_forward(*remembered[i]);
	remembered_len = 0;
	while (scan < old_ptr) {
		void *o = scan + 8;
		scan += obj_bytes(o);
		scan_object(o, minor_forward);
	}
	rt_young_ptr = rt_young_start;
}

// ---- major collection: copy everything live into a fresh to-space.
// Natively the old space alternates between two large reserved regions;
// old_end is a soft limit, set after each major collection to three times the
// live size. Under Emscripten memory is real, so each major collection
// mallocs a to-space sized from what may survive and frees the from-space.

#ifndef __EMSCRIPTEN__
#define REGION (16ull << 30)
static char *regions[2];
static int cur_region;
// pages of each region already faulted in: populated in large batches ahead
// of use, which costs the kernel much less than one fault per 4 KB page
static char *populated[2];
static void populate(char *upto) {
#ifdef MADV_POPULATE_WRITE
	char **hi = &populated[cur_region];
	if (*hi == NULL || *hi < regions[cur_region]) *hi = regions[cur_region];
	if (upto <= *hi) return;
	char *end = (char *)(((uintptr_t)upto + (32u << 20)) & ~(uintptr_t)((2u << 20) - 1));
	if (end > regions[cur_region] + REGION) end = regions[cur_region] + REGION;
	if (madvise(*hi, end - *hi, MADV_POPULATE_WRITE) == 0) *hi = end;
	else *hi = end; // not supported: let pages fault in as before
#else
	(void)upto;
#endif
}
#else
static void populate(char *upto) { (void)upto; }
#endif
static char *from_start, *from_end;

static void *major_forward(void *p) {
	if (!in_young(p) && !((char *)p >= from_start && (char *)p < from_end)) return p;
	if (KIND(p) == K_FWD) return FP(p, 0);
	void *n = copy_to(old_ptr, p);
	old_ptr += obj_bytes(p);
	forward_to(p, n);
	return n;
}

static void major_(size_t need);
static void major(size_t need) {
	double t0 = stats ? now_secs() : 0;
	major_(need);
	if (stats) major_secs += now_secs() - t0;
}

static void major_(size_t need) {
	majors++;
	from_start = old_start;
	from_end = old_ptr;
#ifdef __EMSCRIPTEN__
	// everything in the old and young spaces may survive
	size_t cap = 2 * ((size_t)(old_ptr - old_start) + (size_t)(rt_young_ptr - rt_young_start)) + 4 * minor_size + need;
	if (cap < (32u << 20)) cap = 32u << 20;
	old_start = old_ptr = (char *)malloc(cap);
	if (!old_start) {
		fputs("out of memory\n", stderr);
		exit(2);
	}
#else
	cur_region ^= 1;
	old_start = old_ptr = regions[cur_region];
	if (release_pages) populated[cur_region] = NULL;
	populate(old_start + (from_end - from_start) + (rt_young_ptr - rt_young_start));
#endif
	char *scan = old_ptr;
	if (!gc_bfs) {
		gc_fwd = major_forward;
		scan_roots(fwd_root);
	} else
		scan_roots(major_forward);
	remembered_len = 0;
	while (gc_bfs && scan < old_ptr) {
		void *o = scan + 8;
		scan += obj_bytes(o);
		scan_object(o, major_forward);
	}
	rt_young_ptr = rt_young_start;
#ifdef __EMSCRIPTEN__
	free(from_start);
	old_end = old_start + cap;
#else
	// RT_RELEASE=1 returns the from-space to the kernel; by default it stays
	// resident, so the next major collection copies into faulted-in pages
	if (release_pages) madvise(from_start, from_end - from_start, MADV_DONTNEED);
	size_t live = old_ptr - old_start;
	size_t limit = 3 * live + 4 * minor_size + need;
	if (limit < (64u << 20)) limit = 64u << 20;
	if (limit > REGION) limit = REGION;
	old_end = old_start + limit;
#endif
}

void *rt_alloc_slow(uint64_t header, uint32_t bytes) {
	// a green thread that only computes gives way at each minor collection
	// (before allocating: the caller's live references are rooted here)
	if (rt_nthreads > 1) rt_preempt();
	if (bytes > minor_size / 4) {
		// large objects go straight to the old space
		if ((size_t)(old_end - old_ptr) < bytes) major(bytes);
		char *p = old_ptr;
		old_ptr += bytes;
		*(uint64_t *)p = header;
		memset(p + 8, 0, bytes - 8);
		return p + 8;
	}
	minor();
	char *p = rt_young_ptr;
	rt_young_ptr += bytes;
	*(uint64_t *)p = header;
	memset(p + 8, 0, bytes - 8);
	return p + 8;
}

void rt_write_barrier(void *obj, void **slot, void *val) {
	(void)obj;
	(void)val;
	if (remembered_len == remembered_cap) {
		remembered_cap = remembered_cap ? remembered_cap * 2 : 4096;
		remembered = (void ***)realloc(remembered, remembered_cap * sizeof(void **));
	}
	remembered[remembered_len++] = slot;
}

// after a bulk move or copy of references into obj (memmove in natives): the
// remembered set records slots, so every slot now holding a young pointer is
// recorded again
void rt_barrier_range(void *obj, void **from, int32_t n) {
	if (in_young(obj)) return;
	for (int32_t i = 0; i < n; i++)
		if (in_young(from[i])) rt_write_barrier(obj, &from[i], from[i]);
}

static void report(void) {
	if (stats) fprintf(stderr, "gc: %lu minor (%.2fs), %lu major (%.2fs), old %zu MB used\n", minors, minor_secs, majors, major_secs, (size_t)(old_ptr - old_start) >> 20);
}

// small Int boxes and the two Bool boxes are static
#define SMALL_MIN (-128)
#define SMALL_MAX 1023
static uint64_t small_ints[2 * (SMALL_MAX - SMALL_MIN + 1)];
static uint64_t bool_boxes[4];

void rt_init(int ng, int argc, char **argv) {
	rt_argc = argc;
	rt_argv = argv;
#ifdef __COSMOPOLITAN__
	// an APE build may carry the Haxe standard library in its own zip (site/build.sh)
	if (!getenv("HAXE_STD_PATH") && access("/zip/std/StdTypes.hx", R_OK) == 0) setenv("HAXE_STD_PATH", "/zip/std/", 1);
#endif
	const char *m = getenv("RT_MINOR_KB");
	minor_size = (m ? (size_t)atoi(m) : 4096) << 10;
	stats = getenv("RT_STATS") != NULL;
	release_pages = getenv("RT_RELEASE") != NULL;
	gc_bfs = getenv("RT_BFS") != NULL;
#if defined(MADV_HUGEPAGE) && !defined(__EMSCRIPTEN__)
	// transparent huge pages for the heap: the old space grows by hundreds of
	// MB and is copied into fresh pages, so 4 KB page faults add up
	const char *hp = getenv("RT_HUGE");
	int huge = hp && atoi(hp); // opt-in: it costs more kernel time than it saves here
	rt_young_start = rt_young_ptr = (char *)aligned_alloc(2u << 20, (minor_size + (2u << 20) - 1) & ~(size_t)((2u << 20) - 1));
	if (huge) madvise(rt_young_start, minor_size, MADV_HUGEPAGE);
#else
	rt_young_start = rt_young_ptr = (char *)malloc(minor_size);
#endif
	rt_young_limit = rt_young_start + minor_size;
#ifdef __EMSCRIPTEN__
	old_start = old_ptr = (char *)malloc(32u << 20);
	old_end = old_start + (32u << 20);
	size_t stack_slots = 4u << 20;
#else
	for (int i = 0; i < 2; i++) {
		regions[i] = mmap(NULL, REGION, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE, -1, 0);
		if (regions[i] == MAP_FAILED) {
			fputs("cannot reserve heap\n", stderr);
			exit(2);
		}
#ifdef MADV_HUGEPAGE
		if (huge) madvise(regions[i], REGION, MADV_HUGEPAGE);
#endif
	}
	old_start = old_ptr = regions[0];
	const char *om = getenv("RT_OLD_MB");
	old_end = old_start + ((size_t)(om ? atoi(om) : 256) << 20); // fewer major collections early on
	size_t stack_slots = 16u << 20;
#endif
#ifdef __EMSCRIPTEN__
	rt_stack_base = rt_sp = (void **)calloc(stack_slots, sizeof(void *));
#else
	// reserved, committed as touched, with a guard page above it: as deep as
	// the main C stack (rt_run_main)
	(void)stack_slots;
	size_t sbytes = (size_t)1 << 30, page = (size_t)sysconf(_SC_PAGESIZE);
	char *sstack = mmap(NULL, sbytes + page, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE, -1, 0);
	if (sstack == MAP_FAILED) {
		fputs("cannot reserve the shadow stack\n", stderr);
		exit(2);
	}
	mprotect(sstack + sbytes, page, PROT_NONE);
	rt_stack_base = rt_sp = (void **)sstack;
#endif
	nglobals = ng;
	rt_globals = (void **)calloc(ng + 1, sizeof(void *));
	for (int i = SMALL_MIN; i <= SMALL_MAX; i++) {
		uint64_t *b = &small_ints[2 * (i - SMALL_MIN)];
		b[0] = MKHDR(1, K_OBJ, T_BOXINT);
		*(int32_t *)&b[1] = i;
	}
	for (int i = 0; i < 2; i++) {
		bool_boxes[2 * i] = MKHDR(1, K_OBJ, T_BOXBOOL);
		*(int32_t *)&bool_boxes[2 * i + 1] = i;
	}
	for (int t = 0; t < rt_ntypes; t++) {
		rt_type_objs[2 * t] = MKHDR(1, K_RAW, T_TYPEOBJ);
		*(int32_t *)&rt_type_objs[2 * t + 1] = t;
	}
	atexit(report);
}

// ---- exceptions

#if !(defined(__cplusplus) && defined(__EMSCRIPTEN__))
__attribute__((noreturn)) void rt_throw(void *v) {
	rt_exn = v;
	if (!rt_hcur) {
		char *s = hx_str_to_utf8(hx_std_string(v));
		fprintf(stderr, "Uncaught exception: %s\n", s);
		exit(1);
	}
	RT_LONGJMP(rt_hcur->buf);
}
#endif

__attribute__((noreturn)) void hx_throw_str(const char *msg) {
	rt_throw(hx_str_of_ascii(msg));
}

int32_t hx_f2i(double f) {
	if (!(f == f)) return 0;
	if (f >= 2147483648.0 || f <= -2147483649.0) return (int32_t)(uint32_t)(int64_t)fmod(f, 4294967296.0);
	return (int32_t)f;
}

// ---- boxes

void *hx_box_int(int32_t v) {
	if (v >= SMALL_MIN && v <= SMALL_MAX) return &small_ints[2 * (v - SMALL_MIN) + 1];
	void *b = rt_alloc_init(1, T_BOXINT, K_OBJ);
	FP(b, 0) = 0;
	FI(b, 0) = v;
	return b;
}

void *hx_box_float(double v) {
	void *b = rt_alloc_init(1, T_BOXFLOAT, K_OBJ);
	FD(b, 0) = v;
	return b;
}

void *hx_box_bool(int32_t v) {
	return &bool_boxes[v ? 3 : 1];
}

int32_t hx_unbox_int(void *v) {
	if (!v) return 0;
	switch (TINDEX(v)) {
	case T_BOXINT:
	case T_BOXBOOL: return FI(v, 0);
	case T_BOXFLOAT: return hx_f2i(FD(v, 0));
	default: return 0;
	}
}

double hx_unbox_float(void *v) {
	if (!v) return 0;
	switch (TINDEX(v)) {
	case T_BOXINT:
	case T_BOXBOOL: return FI(v, 0);
	case T_BOXFLOAT: return FD(v, 0);
	default: return 0;
	}
}

int32_t hx_unbox_bool(void *v) {
	if (!v) return 0;
	switch (TINDEX(v)) {
	case T_BOXINT:
	case T_BOXBOOL: return FI(v, 0) != 0;
	case T_BOXFLOAT: return FD(v, 0) != 0;
	default: return 1;
	}
}

// ---- arrays

// data for at least `cap` elements; *real: the capacity in elements
static void *data_alloc(int32_t kind, int32_t cap, int32_t *real) {
	if (cap < 4) cap = 4;
	switch (kind) {
	case AK_I32:
		*real = (cap + 1) & ~1;
		return rt_alloc((cap + 1) / 2, T_ADATA_RAW, K_RAW);
	case AK_F64: *real = cap; return rt_alloc(cap, T_ADATA_RAW, K_RAW);
	default: *real = cap; return rt_alloc(cap, T_ADATA_P, K_PARR);
	}
}

// arrays with elements (empty arrays have no data until the first store: rt.h)
void *hx_arr_new_n(int32_t kind, int32_t len) {
	int32_t cap;
	void *d = data_alloc(kind, len, &cap);
	RT_ROOT(d);
	void *a = rt_alloc(3, T_ARRAY, K_OBJ);
	RT_RELOAD(d);
	RT_UNROOT(1);
	ARR_LEN(a) = len;
	ARR_KIND(a) = kind;
	ARR_CAP(a) = cap;
	FP(a, 1) = d; // a is young
	if (!in_young(a)) rt_set_ptr(a, &FP(a, 1), d);
	return a;
}

// room for `need` elements
void hx_arr_grow(void **slot, int32_t need) {
	void *a = *slot;
	uint32_t cap = ARR_CAP(a);
	if ((uint32_t)need <= cap) return;
	uint32_t ncap = cap * 2;
	if (ncap < (uint32_t)need) ncap = need;
	int32_t real;
	void *nd = data_alloc(ARR_KIND(a), ncap, &real);
	a = *slot;
	ARR_CAP(a) = real;
	void *d = ARR_DATA(a);
	uint32_t len = ARR_LEN(a);
	switch (ARR_KIND(a)) {
	case AK_I32: memcpy(nd, d, 4 * len); break;
	case AK_F64: memcpy(nd, d, 8 * len); break;
	default:
		memcpy(nd, d, 8 * len);
		// large data is allocated old: its elements may point to young objects
		if (!in_young(nd))
			for (uint32_t i = 0; i < len; i++)
				if (in_young(FP(nd, i))) rt_write_barrier(nd, &FP(nd, i), FP(nd, i));
		break;
	}
	rt_set_ptr(a, &ARR_DATA(a), nd);
}

// convert an Int/Float array to boxed elements (generic code stored something else)
void hx_arr_to_ptr(void **slot) {
	void *a = *slot;
	if (ARR_KIND(a) == AK_PTR) return;
	uint32_t len = ARR_LEN(a);
	int32_t real;
	void *nd = data_alloc(AK_PTR, len, &real);
	RT_ROOT(nd);
	for (uint32_t i = 0; i < len; i++) {
		a = *slot;
		void *v = ARR_KIND(a) == AK_I32 ? hx_box_int(((int32_t *)ARR_DATA(a))[i]) : hx_box_float(((double *)ARR_DATA(a))[i]);
		RT_RELOAD(nd);
		rt_set_ptr(nd, &FP(nd, i), v);
	}
	RT_RELOAD(nd);
	RT_UNROOT(1);
	a = *slot;
	ARR_KIND(a) = AK_PTR;
	ARR_CAP(a) = real;
	rt_set_ptr(a, &ARR_DATA(a), nd);
}

int32_t hx_aget_i_slow(void *a, int32_t i) {
	if (!a || (uint32_t)i >= (uint32_t)ARR_LEN(a)) return 0;
	switch (ARR_KIND(a)) {
	case AK_I32: return ((int32_t *)ARR_DATA(a))[i];
	case AK_F64: return hx_f2i(((double *)ARR_DATA(a))[i]);
	default: return hx_unbox_int(FP(ARR_DATA(a), i));
	}
}

double hx_aget_f_slow(void *a, int32_t i) {
	if (!a || (uint32_t)i >= (uint32_t)ARR_LEN(a)) return 0;
	switch (ARR_KIND(a)) {
	case AK_I32: return ((int32_t *)ARR_DATA(a))[i];
	case AK_F64: return ((double *)ARR_DATA(a))[i];
	default: return hx_unbox_float(FP(ARR_DATA(a), i));
	}
}

void *hx_aget_p_slow(void *a, int32_t i) {
	if (!a || (uint32_t)i >= (uint32_t)ARR_LEN(a)) return 0;
	switch (ARR_KIND(a)) {
	case AK_I32: return hx_box_int(((int32_t *)ARR_DATA(a))[i]);
	case AK_F64: return hx_box_float(((double *)ARR_DATA(a))[i]);
	default: return FP(ARR_DATA(a), i);
	}
}

// store v (of kind vk; AK_PTR: v is the address of a rooted slot) at i < length
static void store_conv(void **slot, int32_t i, int32_t vk, uint64_t v) {
	void *a = *slot;
	int32_t ak = ARR_KIND(a);
	if (ak == AK_PTR) {
		void *p;
		switch (vk) {
		case AK_I32: p = hx_box_int((int32_t)v); break;
		case AK_F64: { double d; memcpy(&d, &v, 8); p = hx_box_float(d); break; }
		default: p = *(void **)(uintptr_t)v; break;
		}
		a = *slot;
		rt_set_ptr(ARR_DATA(a), &FP(ARR_DATA(a), i), p);
		return;
	}
	if (vk == AK_PTR) {
		void *p = *(void **)(uintptr_t)v;
		int num = !p || TINDEX(p) == T_BOXINT || TINDEX(p) == T_BOXFLOAT || TINDEX(p) == T_BOXBOOL;
		if (!num || (ak == AK_I32 && TINDEX(p) == T_BOXFLOAT)) {
			hx_arr_to_ptr(slot);
			store_conv(slot, i, vk, v);
			return;
		}
		if (ak == AK_I32) ((int32_t *)ARR_DATA(a))[i] = hx_unbox_int(p);
		else ((double *)ARR_DATA(a))[i] = hx_unbox_float(p);
		return;
	}
	double d;
	memcpy(&d, &v, 8);
	if (ak == AK_I32 && vk == AK_F64) {
		hx_arr_to_ptr(slot);
		store_conv(slot, i, vk, v);
		return;
	}
	if (ak == AK_I32) ((int32_t *)ARR_DATA(a))[i] = (int32_t)v;
	else ((double *)ARR_DATA(a))[i] = vk == AK_I32 ? (double)(int32_t)v : d;
}

void hx_aset_slow(void **slot, int32_t i, int32_t vk, uint64_t v) {
	if (i < 0) return;
	void *a = *slot;
	if ((uint32_t)i >= (uint32_t)ARR_LEN(a)) {
		hx_arr_grow(slot, i + 1);
		a = *slot;
		ARR_LEN(a) = i + 1; // the data is zeroed: new elements are 0 / null
	}
	store_conv(slot, i, vk, v);
}

void hx_apush_slow(void **slot, int32_t vk, uint64_t v) {
	void *a = *slot;
	int32_t n = ARR_LEN(a);
	hx_arr_grow(slot, n + 1);
	a = *slot;
	ARR_LEN(a) = n + 1;
	store_conv(slot, n, vk, v);
}
