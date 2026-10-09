// EXPERIMENTAL runtime for the C output of backend/; see rt.h.
#include "rt.h"
#include <stdio.h>
#include <stdlib.h>
#include <sys/mman.h>

char *rt_young_start, *rt_young_ptr, *rt_young_limit;
static char *old_start, *old_ptr, *old_end;
void **rt_sp;
static void **stack_base;
void **rt_globals;
static int nglobals;
rt_handler *rt_hcur;
void *rt_exn;
static void ***remembered;
static size_t remembered_len, remembered_cap;
static size_t minor_size;
static int stats;
static unsigned long minors, majors;

static char *copy_to(char *dst, void *obj) {
	uint32_t bytes = 8 * (NSLOTS(obj) + 1);
	memcpy(dst, (char *)obj - 8, bytes);
	return dst + 8;
}

static inline int in_young(void *p) {
	return (char *)p >= rt_young_start && (char *)p < rt_young_limit;
}

// ---- minor collection: copy live nursery objects to the end of the old space

static inline void *minor_forward(void *p) {
	if (!in_young(p)) return p;
	if (KIND(p) == K_FWD) return FP(p, 0);
	void *n = copy_to(old_ptr, p);
	old_ptr += 8 * (NSLOTS(p) + 1);
	HDR(p) = (uint64_t)K_FWD << 48 | NSLOTS(p);
	FP(p, 0) = n;
	return n;
}

static void scan_object(void *o, void *(*fwd)(void *)) {
	uint32_t n = NSLOTS(o);
	switch (KIND(o)) {
	case K_OBJ: {
		uint64_t m = rt_type_ptrmaps[TINDEX(o)];
		while (m) {
			int i = __builtin_ctzll(m);
			m &= m - 1;
			if (FP(o, i)) FP(o, i) = fwd(FP(o, i));
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

static void major(size_t need);

static void minor(void) {
	size_t young_used = rt_young_ptr - rt_young_start;
	if ((size_t)(old_end - old_ptr) < young_used + 64) {
		major(0);
		return;
	}
	minors++;
	char *scan = old_ptr;
	for (void **s = stack_base; s < rt_sp; s++)
		if (*s) *s = minor_forward(*s);
	for (int i = 0; i < nglobals; i++)
		if (rt_globals[i]) rt_globals[i] = minor_forward(rt_globals[i]);
	if (rt_exn) rt_exn = minor_forward(rt_exn);
	for (size_t i = 0; i < remembered_len; i++)
		if (*remembered[i]) *remembered[i] = minor_forward(*remembered[i]);
	remembered_len = 0;
	while (scan < old_ptr) {
		void *o = scan + 8;
		scan += 8 * (NSLOTS(o) + 1);
		scan_object(o, minor_forward);
	}
	rt_young_ptr = rt_young_start;
}

// ---- major collection: copy everything live into a fresh old space

static char *from_start, *from_end;
static inline void *major_forward(void *p) {
	if (!in_young(p) && !((char *)p >= from_start && (char *)p < from_end)) return p;
	if (KIND(p) == K_FWD) return FP(p, 0);
	void *n = copy_to(old_ptr, p);
	old_ptr += 8 * (NSLOTS(p) + 1);
	HDR(p) = (uint64_t)K_FWD << 48 | NSLOTS(p);
	FP(p, 0) = n;
	return n;
}

// The old space alternates between two large reserved regions; old_end is a
// soft limit, set after each major collection to three times the live size.
#ifdef __EMSCRIPTEN__
#define REGION (640u << 20) // wasm32: the regions are real memory
#else
#define REGION (16ull << 30)
#endif
static char *regions[2];
static int cur_region;

static void major(size_t need) {
	majors++;
	from_start = old_start;
	from_end = old_ptr;
	cur_region ^= 1;
	old_start = old_ptr = regions[cur_region];
	char *scan = old_ptr;
	for (void **s = stack_base; s < rt_sp; s++)
		if (*s) *s = major_forward(*s);
	for (int i = 0; i < nglobals; i++)
		if (rt_globals[i]) rt_globals[i] = major_forward(rt_globals[i]);
	if (rt_exn) rt_exn = major_forward(rt_exn);
	remembered_len = 0;
	while (scan < old_ptr) {
		void *o = scan + 8;
		scan += 8 * (NSLOTS(o) + 1);
		scan_object(o, major_forward);
	}
#ifndef __EMSCRIPTEN__
	madvise(from_start, from_end - from_start, MADV_DONTNEED);
#endif
	rt_young_ptr = rt_young_start;
	size_t live = old_ptr - old_start;
	size_t limit = 3 * live + 4 * minor_size + need;
	if (limit < (32u << 20)) limit = 32u << 20;
	old_end = old_start + limit;
}

void *rt_alloc_slow(uint64_t header, uint32_t bytes) {
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
		remembered_cap = remembered_cap ? remembered_cap * 2 : 1024;
		remembered = realloc(remembered, remembered_cap * sizeof(void **));
	}
	remembered[remembered_len++] = slot;
}

static void report(void) {
	if (stats) fprintf(stderr, "gc: %lu minor, %lu major, old %zu KB\n", minors, majors, (size_t)(old_end - old_start) >> 10);
}

void rt_init(int ng) {
	const char *m = getenv("RT_MINOR_KB");
	minor_size = (m ? (size_t)atoi(m) : 2048) << 10;
	stats = getenv("RT_STATS") != NULL;
	rt_young_start = rt_young_ptr = malloc(minor_size);
	rt_young_limit = rt_young_start + minor_size;
	for (int i = 0; i < 2; i++) {
#ifdef __EMSCRIPTEN__
		regions[i] = malloc(REGION); // Emscripten's mmap zero-fills eagerly
		if (!regions[i]) {
#else
		regions[i] = mmap(NULL, REGION, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE, -1, 0);
		if (regions[i] == MAP_FAILED) {
#endif
			fputs("cannot reserve heap\n", stderr);
			exit(2);
		}
	}
	old_start = old_ptr = regions[0];
	old_end = old_start + (32u << 20);
	size_t stack_slots = 8u << 20;
	stack_base = rt_sp = calloc(stack_slots, sizeof(void *));
	nglobals = ng;
	rt_globals = calloc(ng + 1, sizeof(void *));
	atexit(report);
}

__attribute__((noreturn)) void rt_throw(void *v) {
	rt_exn = v;
	if (!rt_hcur) {
		fputs("Uncaught exception\n", stderr);
		exit(1);
	}
	RT_LONGJMP(rt_hcur->buf);
}

void *rt_arr_new(int raw, int32_t cap, uint32_t tindex) {
	if (cap < 4) cap = 4;
	void **slot = rt_sp++;
	*slot = rt_alloc(raw ? (uint32_t)(cap + 1) / 2 : (uint32_t)cap, 0, raw ? K_RAW : K_PARR);
	void *a = rt_alloc(2, tindex, K_OBJ);
	FP(a, 1) = *slot; // a is young: no barrier needed
	rt_sp--;
	return a;
}

void rt_arr_grow(void **arr_slot, int raw) {
	void *d = ARR_DATA(*arr_slot);
	uint32_t cap = raw ? NSLOTS(d) * 2 : NSLOTS(d);
	uint32_t ncap = cap < 4 ? 4 : cap * 2;
	void *nd = rt_alloc(raw ? ncap / 2 : ncap, 0, raw ? K_RAW : K_PARR);
	void *a = *arr_slot; // may have moved
	d = ARR_DATA(a);
	memcpy(nd, d, 8 * NSLOTS(d));
	rt_set_ptr(a, &ARR_DATA(a), nd);
	// large data arrays are allocated old: their elements may point to young objects
	if (!raw && !in_young(nd))
		for (uint32_t i = 0; i < NSLOTS(d); i++)
			if (in_young(FP(nd, i))) rt_write_barrier(nd, &FP(nd, i), FP(nd, i));
}
