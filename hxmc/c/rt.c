// The runtime of hxmc's programs; see rt.h.
// GC, startup, exceptions, boxes, arrays.
#define _GNU_SOURCE
#include "rt_gc.h"
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#ifdef _WIN32
#include "rt_win.h" // mmap and friends over reservations committed on first touch
#include <shellapi.h>
#else
#include <sys/mman.h>
#include <unistd.h>
#endif


// Threads (rt_thread.c): each thread allocates in its own chunk of the
// nursery (TLAB: rt_young_ptr/rt_young_limit, taken from young_next) and
// records old-to-young stores in its own remembered set (rt_mutator); a
// collection stops every other thread at a safepoint (an allocation slow
// path) or in a safe region (a blocking native), see rt_world_stop. With one
// thread a TLAB is a chunk of 32 KB (RT_ZCHUNK_KB).
//
// Allocation zeroes in bulk: a TLAB is zeroed when it is taken (in the L1
// cache, right before the allocations that use it), so every object allocated in the
// nursery starts zeroed and no allocation zeroes its own slots. Two limits:
// rt_young_rlimit is the TLAB's end, compared by allocations whose every slot
// is written before it is read (Mem.allocRaw); rt_young_limit, compared by
// those that rely on the zeros, is the same but with RT_VERIFY=1, where the
// free nursery holds a byte pattern instead of zeros and it is NULL: those
// allocations then take the slow path, which zeroes them, while the others
// still read the pattern if they read before writing.
char *rt_young_start, *rt_young_end;
static char *young_next; // free part of the nursery: TLABs are taken from here
static char *young_dirty; // the nursery above this holds zeros (never used since fresh or released)
RT_TLS char *rt_young_ptr, *rt_young_limit, *rt_young_rlimit;
static char *old_start, *old_ptr, *old_end;
RT_TLS void **rt_sp;
RT_TLS void **rt_sp_hw;
RT_TLS void **rt_stack_base; // the running thread's shadow stack
void **rt_globals;
static int nglobals;
RT_TLS rt_handler *rt_hcur;
RT_TLS void *rt_exn;
RT_TLS rt_mutator *rt_mut;
static size_t tlab_size; // with several threads (RT_TLAB_KB; default a 16th of the nursery)
static size_t minor_size;
static int stats;
#ifdef RT_CENSUS_BUILD
// (a debug build of the runtime object: HXMC_RT_CENSUS=1 hxmc/c/mkrt.sh)
static int census; // RT_CENSUS: 1 at exit, 2 also after each major collection
static void census_now(const char *when);
#endif
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
	return (char *)p >= rt_young_start && (char *)p < rt_young_end;
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

// ---- finalisers (Gc.finalise in Eval): OCaml's Gc.finalise semantics. A
// finaliser's function is a root; its value is a root of minor collections
// only (they promote it), and a major collection that finds it unreachable
// copies it back (it lives on for the call) and queues the call. Queued calls
// run at the next allocation slow path or rt_gc_run_finalisers, in the
// reverse order of registration for values found dead together.
typedef struct {
	void *fn, *val;
} rt_final;
static rt_final *finals, *final_queue;
static size_t nfinals, finals_cap, final_qhead, final_qlen, final_qcap;
static RT_TLS int finals_running;
static rt_lock_t finals_lock = RT_LOCK_INIT; // registration and dequeuing (the collector runs with every thread stopped)

// ---- native handles: freed once their T_NATIVE object is found unreachable
typedef struct {
	void *obj, *p;
	void (*free_fn)(void *);
} rt_native;
static rt_native *natives;
static size_t nnatives, natives_cap;
static rt_lock_t natives_lock = RT_LOCK_INIT;

void *rt_native_new(void *p, void (*free_fn)(void *)) { return rt_native_new_refs(p, free_fn, 0); }

// with nrefs reference slots after the handle (slots 1..nrefs, NULL at first,
// set with rt_set_ptr): what the C resource points into stays alive while the
// handle does. The object is then K_PARR; slot 0 (outside the heap) is left
// alone by the collector.
void *rt_native_new_refs(void *p, void (*free_fn)(void *), uint32_t nrefs) {
	void *o = rt_alloc(1 + nrefs, T_NATIVE, nrefs ? K_PARR : K_RAW);
	FP(o, 0) = p;
	for (uint32_t i = 1; i <= nrefs; i++)
		FP(o, i) = NULL;
	rt_lock(&natives_lock);
	if (nnatives == natives_cap) {
		natives_cap = natives_cap ? natives_cap * 2 : 256;
		natives = (rt_native *)realloc(natives, natives_cap * sizeof(rt_native));
	}
	natives[nnatives].obj = o;
	natives[nnatives].p = p;
	natives[nnatives++].free_fn = free_fn;
	rt_unlock(&natives_lock);
	return o;
}

// after a collection of the nursery (and of [lo, hi) for a major one). The
// handles found dead together are freed newest first: a resource that points
// into another one (an SSL context into its configuration) is usually created
// after it.
static rt_native *dead_natives;
static size_t dead_cap;
static void sweep_natives(char *lo, char *hi) {
	size_t live = 0, ndead = 0;
	for (size_t i = 0; i < nnatives; i++) {
		void *o = natives[i].obj;
		if (in_young(o) || ((char *)o >= lo && (char *)o < hi)) {
			if (KIND(o) != K_FWD) {
				if (ndead == dead_cap) {
					dead_cap = dead_cap ? dead_cap * 2 : 64;
					dead_natives = (rt_native *)realloc(dead_natives, dead_cap * sizeof(rt_native));
				}
				dead_natives[ndead++] = natives[i];
				continue;
			}
			o = FP(o, 0);
		}
		natives[live] = natives[i];
		natives[live++].obj = o;
	}
	nnatives = live;
	while (ndead) {
		ndead--;
		dead_natives[ndead].free_fn(dead_natives[ndead].p);
	}
}

static void scan_roots(void *(*fwd)(void *)) {
	for (void **s = rt_stack_base; s < rt_sp; s++)
		if (*s) *s = fwd(*s);
	rt_threads_scan(fwd); // the other threads' shadow stacks, entry closures, Tls values
	for (int i = 0; i < nglobals; i++)
		if (rt_globals[i]) rt_globals[i] = fwd(rt_globals[i]);
	if (rt_exn) rt_exn = fwd(rt_exn);
	for (size_t i = 0; i < nfinals; i++)
		finals[i].fn = fwd(finals[i].fn);
	for (size_t i = final_qhead; i < final_qlen; i++) {
		final_queue[i].fn = fwd(final_queue[i].fn);
		final_queue[i].val = fwd(final_queue[i].val);
	}
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
static void run_finalisers(int propagate);

static void minor_(void);
static void minor(void) {
	double t0 = stats ? now_secs() : 0;
	unsigned long m0 = majors;
	minor_();
	if (majors == m0) sweep_natives(NULL, NULL);
	if (stats && majors == m0) minor_secs += now_secs() - t0;
}

static void *(*rem_fwd)(void *);
static void scan_object(void *o, void *(*fwd)(void *));
static void forget_objs(rt_mutator *m) {
	m->robjs_len = 0;
	memset(m->robjs_recent, 0, sizeof m->robjs_recent);
}

static void forward_remembered(rt_mutator *m, void *arg) {
	(void)arg;
	for (size_t i = 0; i < m->rem_len; i++)
		if (*m->rem[i]) *m->rem[i] = rem_fwd(*m->rem[i]);
	m->rem_len = 0;
	for (size_t i = 0; i < m->robjs_len; i++)
		scan_object(m->robjs[i], rem_fwd);
	forget_objs(m);
}

static void clear_remembered(rt_mutator *m, void *arg) {
	(void)arg;
	m->rem_len = 0;
	forget_objs(m);
}

static void minor_(void) {
	size_t young_used = young_next - rt_young_start;
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
		for (size_t i = 0; i < nfinals; i++)
			finals[i].val = fwd_root(finals[i].val);
		rem_fwd = fwd_root;
		rt_mutators_foreach(forward_remembered, NULL);
		return;
	}
	scan_roots(minor_forward);
	for (size_t i = 0; i < nfinals; i++)
		finals[i].val = minor_forward(finals[i].val);
	rem_fwd = minor_forward;
	rt_mutators_foreach(forward_remembered, NULL);
	while (scan < old_ptr) {
		void *o = scan + 8;
		scan += obj_bytes(o);
		scan_object(o, minor_forward);
	}
}

// ---- major collection: copy everything live into a fresh to-space.
// The old space alternates between two large reserved regions; old_end is a
// soft limit, set after each major collection to three times the live size.

// 16 GB each; on Windows
// they are 2 GB by default (RT_REGION_MB), and a reservation that fails is
// retried at half the size down to 512 MB
static size_t region_bytes = 16ull << 30;
#define REGION region_bytes
static char *regions[2];
static int cur_region;
// pages of each region already faulted in: populated in large batches ahead
// of use, which costs the kernel much less than one fault per 4 KB page. The
// batch is an eighth of the space in use, between 4 MB and 32 MB
// (RT_AHEAD_MB), so a small program does not fault in memory it never uses.
static char *populated[2];
static size_t populate_ahead = 32u << 20; // RT_AHEAD_MB
static void populate(char *upto) {
#ifdef MADV_POPULATE_WRITE
	char **hi = &populated[cur_region];
	if (*hi == NULL || *hi < regions[cur_region]) *hi = regions[cur_region];
	if (upto <= *hi) return;
	size_t ahead = (size_t)(upto - regions[cur_region]) / 8;
	if (ahead < (4u << 20)) ahead = 4u << 20;
	if (ahead > populate_ahead) ahead = populate_ahead;
	char *end = (char *)(((uintptr_t)upto + ahead) & ~(uintptr_t)((2u << 20) - 1));
	if (end > regions[cur_region] + REGION) end = regions[cur_region] + REGION;
	if (madvise(*hi, end - *hi, MADV_POPULATE_WRITE) == 0) *hi = end;
	else *hi = end; // not supported: let pages fault in as before
#else
	(void)upto;
#endif
}
#ifdef MADV_POPULATE_WRITE
#define POPULATE_AHEAD(bytes) \
	if (__builtin_expect(old_ptr + (bytes) > populated[cur_region], 0)) populate(old_ptr + (bytes))
#else
#define POPULATE_AHEAD(bytes)
#endif
static char *from_start, *from_end;

static void *major_forward(void *p) {
	if (!in_young(p) && !((char *)p >= from_start && (char *)p < from_end)) return p;
	if (KIND(p) == K_FWD) return FP(p, 0);
	POPULATE_AHEAD(obj_bytes(p)); // the to-space is faulted in as the copy reaches it
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
	// pages faulted in ahead of the from-space's end are not needed now
	if (release_pages && populated[cur_region] > from_end) {
		char *lo = (char *)(((uintptr_t)from_end + 4095) & ~(uintptr_t)4095);
		if (populated[cur_region] > lo) madvise(lo, populated[cur_region] - lo, MADV_DONTNEED);
		populated[cur_region] = lo;
	}
	cur_region ^= 1;
	old_start = old_ptr = regions[cur_region];
	populate(old_start + 1);
	char *scan = old_ptr;
	if (!gc_bfs) {
		gc_fwd = major_forward;
		scan_roots(fwd_root);
	} else
		scan_roots(major_forward);
	rt_mutators_foreach(clear_remembered, NULL);
	while (gc_bfs && scan < old_ptr) {
		void *o = scan + 8;
		scan += obj_bytes(o);
		scan_object(o, major_forward);
	}
	if (nfinals) {
		// values not copied yet are unreachable: queue their calls (newest
		// first), then copy them and what they reach
		size_t live = 0, q0 = final_qlen;
		for (size_t i = nfinals; i-- > 0;) {
			void *v = finals[i].val;
			int collected = in_young(v) || ((char *)v >= from_start && (char *)v < from_end);
			if (collected && KIND(v) != K_FWD) {
				if (final_qlen == final_qcap) {
					final_qcap = final_qcap ? final_qcap * 2 : 64;
					final_queue = (rt_final *)realloc(final_queue, final_qcap * sizeof(rt_final));
				}
				final_queue[final_qlen++] = finals[i];
				finals[i].fn = NULL;
			}
		}
		for (size_t i = 0; i < nfinals; i++)
			if (finals[i].fn) {
				void *v = finals[i].val;
				if (in_young(v) || ((char *)v >= from_start && (char *)v < from_end)) v = FP(v, 0);
				finals[live].fn = finals[i].fn;
				finals[live++].val = v;
			}
		nfinals = live;
		for (size_t i = q0; i < final_qlen; i++)
			final_queue[i].val = gc_bfs ? major_forward(final_queue[i].val) : fwd_root(final_queue[i].val);
		while (gc_bfs && scan < old_ptr) {
			void *o = scan + 8;
			scan += obj_bytes(o);
			scan_object(o, major_forward);
		}
	}
	sweep_natives(from_start, from_end);
	// the from-space goes back to the kernel (RT_RELEASE=0 keeps it resident,
	// so the next major collection copies into faulted-in pages: a little
	// less system time for as much more memory as the old space held)
	if (release_pages) {
		char *hi = populated[cur_region ^ 1] > from_end ? populated[cur_region ^ 1] : from_end; // with the pages faulted in ahead
		madvise(from_start, hi - from_start, MADV_DONTNEED);
		populated[cur_region ^ 1] = regions[cur_region ^ 1];
	}
	size_t live = old_ptr - old_start;
	size_t limit = 3 * live + 4 * minor_size + need;
	if (limit < (64u << 20)) limit = 64u << 20;
	if (limit > REGION) limit = REGION;
	old_end = old_start + limit;
	if (stats) fprintf(stderr, "gc: major %lu: %zu MB live of %zu MB, limit %zu MB\n", majors, (size_t)(old_ptr - old_start) >> 20, (size_t)(from_end - from_start) >> 20, (size_t)(old_end - old_start) >> 20);
#ifdef RT_CENSUS_BUILD
	if (census == 2) census_now("major collection");
#endif
}

// the nursery is empty again: every thread takes a new TLAB at its next allocation
static void reset_tlab(rt_mutator *m, void *arg) {
	(void)arg;
	*m->yptr_ref = NULL;
	*m->ylim_ref = NULL;
	*m->yrlim_ref = NULL;
}

static int huge_pages; // RT_HUGE
static int minor_fixed; // RT_MINOR_KB sets the nursery size
#define MINOR_MAX ((size_t)32 << 20)

// The nursery: a reserved range (pages committed as touched) that it grows
// and shrinks in, so resizing allocates nothing.
static char *nursery_alloc(size_t bytes) {
	size_t reserve = bytes > MINOR_MAX ? bytes : MINOR_MAX;
	char *p = mmap(NULL, reserve + (2u << 20), PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE, -1, 0);
	if (p == MAP_FAILED) {
		fputs("cannot reserve the nursery\n", stderr);
		exit(2);
	}
	p = (char *)(((uintptr_t)p + (2u << 20) - 1) & ~(uintptr_t)((2u << 20) - 1)); // 2 MB aligned (huge pages)
#ifdef MADV_HUGEPAGE
	if (huge_pages) madvise(p, reserve, MADV_HUGEPAGE);
#endif
	return p;
}

// After a minor collection where much of the nursery survived (objects that
// live a little longer than a nursery cycle, e.g. a tree being built), a
// larger nursery copies them fewer times: double it. It is empty now.
// It pays only when the survivors stay about the same with a larger nursery
// (they are copied once per collection); when they grow with it (everything
// lives long), the growth is undone and not tried again.
static size_t grown_from, survived_before_growth;
#define GROWTH_UNSUPPORTED 0
static int growth_off;

static void resize_nursery(size_t size) {
	if (size < minor_size && madvise(rt_young_start + size, minor_size - size, MADV_DONTNEED) == 0) {
		// zeros again above (pages are released whole: the partial page below
		// the next 64 KB boundary stays dirty)
		char *z = rt_young_start + ((size + 0xFFFF) & ~(size_t)0xFFFF);
		if (z < young_dirty) young_dirty = z;
	}
	minor_size = size;
	rt_young_end = rt_young_start + minor_size;
	if (!getenv("RT_TLAB_KB")) tlab_size = minor_size / 16;
	if (stats) fprintf(stderr, "gc: nursery %zu KB\n", minor_size >> 10);
}

static void adapt_nursery(size_t survived) {
	if (grown_from) {
		if (survived > survived_before_growth + survived_before_growth / 2) {
			resize_nursery(grown_from);
			growth_off = 1;
		}
		grown_from = 0;
	} else if (!growth_off && !GROWTH_UNSUPPORTED && minor_size < MINOR_MAX && survived * 8 > minor_size) {
		grown_from = minor_size;
		survived_before_growth = survived;
		resize_nursery(minor_size * 2);
	}
}

// the slots a thread's frames left above its stack top (see rt_sp_hw)
void rt_zero_above(void **sp, void ***hw) {
	if (*hw > sp) memset(sp, 0, (size_t)((char *)*hw - (char *)sp));
	*hw = sp;
}

static void zero_mutator_stack(rt_mutator *m, void *arg) {
	(void)arg;
	rt_zero_above(*m->sp_ref, m->hw_ref);
}

// RT_VERIFY=1: the free nursery is filled with a byte pattern at startup and
// after every collection, so that an allocation that is not initialized reads
// the pattern from its first use (not zeros before the first collection and
// dead objects after it), and so does a reference a collection did not see
// (a missing root: the object it pointed to has moved)
static int poison;
#define POISON 0xA5

// a collection, with every other thread stopped (unless another thread
// collected meanwhile: the caller then retries its allocation)
static void collect(int full, size_t need) {
	if (!rt_world_stop()) return;
	if (young_next > young_dirty) young_dirty = young_next;
	if (full) major(need);
	else {
		char *before = old_ptr;
		unsigned long m0 = majors;
		minor();
		if (!minor_fixed && majors == m0) adapt_nursery((size_t)(old_ptr - before));
	}
	young_next = rt_young_start;
	if (poison) memset(rt_young_start, POISON, minor_size);
	rt_mutators_foreach(reset_tlab, NULL);
	rt_zero_above(rt_sp, &rt_sp_hw);
	rt_mutators_foreach(zero_mutator_stack, NULL);
	rt_world_resume();
}

// a TLAB with room for `bytes`, zeroed (but under RT_VERIFY: the pattern;
// the whole free nursery then with one thread). The rest of the thread's
// TLAB starts it when that was the last one taken (with one thread, always:
// the free nursery stays contiguous). young_dirty changes only while the
// world is stopped.
static size_t zchunk; // RT_ZCHUNK_KB
// x86-64: rep stosb (fast strings: whole cache lines written without being
// read first), measured faster here than the runtime's memset's rep stosq
static inline void zero_bytes(char *d, size_t n) {
#ifdef __x86_64__
	__asm__ volatile("rep stosb" : "+D"(d), "+c"(n) : "a"(0) : "memory");
#else
	memset(d, 0, n);
#endif
}
static int tlab_refill(uint32_t bytes) {
	size_t want = RT_NTHREADS() > 1 ? tlab_size : poison ? (size_t)-1 : zchunk;
	if (want < bytes) want = bytes;
	char *p = __atomic_load_n(&young_next, __ATOMIC_RELAXED);
	for (;;) {
		char *s = rt_young_ptr && p == rt_young_rlimit ? rt_young_ptr : p;
		size_t avail = (size_t)(rt_young_end - s);
		if (avail < bytes) return 0;
		char *e = s + (want < avail ? want : avail);
		if (__atomic_compare_exchange_n(&young_next, &p, e, 1, __ATOMIC_RELAXED, __ATOMIC_RELAXED)) {
			// (below p: the rest of the thread's TLAB, zeroed already)
			if (!poison && p < young_dirty) zero_bytes(p, (size_t)((e < young_dirty ? e : young_dirty) - p));
			rt_young_ptr = s;
			rt_young_rlimit = e;
			rt_young_limit = poison ? NULL : e;
			return 1;
		}
	}
}

// room for `bytes` in the thread's TLAB, refilled if needed (0: the nursery is full)
static inline int young_room(uint32_t bytes) {
	return rt_young_rlimit - rt_young_ptr >= (intptr_t)bytes || tlab_refill(bytes);
}

void *rt_alloc_slow(uint64_t header, uint32_t bytes) {
	// a safepoint: the caller's live references are rooted here
	rt_safepoint();
	// likewise for finaliser calls queued by an earlier major collection
	if (__atomic_load_n(&final_qlen, __ATOMIC_RELAXED) && !finals_running) run_finalisers(0);
	char *p;
	// large objects go straight to the old space (with one thread, unless the
	// free nursery has room: they may die young)
	if (bytes > minor_size / 4 && !(RT_NTHREADS() == 1 && young_room(bytes))) {
		p = __atomic_load_n(&old_ptr, __ATOMIC_RELAXED);
		for (;;) {
			if ((size_t)(old_end - p) < bytes) {
				collect(1, bytes);
				p = __atomic_load_n(&old_ptr, __ATOMIC_RELAXED);
				continue;
			}
			if (__atomic_compare_exchange_n(&old_ptr, &p, p + bytes, 1, __ATOMIC_RELAXED, __ATOMIC_RELAXED)) break;
		}
	} else {
		while (!young_room(bytes)) collect(0, 0); // (room already: another thread collected meanwhile)
		p = rt_young_ptr;
		rt_young_ptr += bytes;
		*(uint64_t *)p = header;
		// (zeroed with its TLAB, but for the pattern of RT_VERIFY)
		if (poison) memset(p + 8, 0, bytes - 8);
		return p + 8;
	}
	*(uint64_t *)p = header;
	memset(p + 8, 0, bytes - 8);
	return p + 8;
}

// Gc.finalise f v: values outside the heap (static objects, null) are never
// collected, so their finalisers never run
void rt_gc_finalise(void *fn, void *val) {
	if (!val || !(in_young(val) || ((char *)val >= old_start && (char *)val < old_ptr))) return;
	rt_lock(&finals_lock);
	if (nfinals == finals_cap) {
		finals_cap = finals_cap ? finals_cap * 2 : 64;
		finals = (rt_final *)realloc(finals, finals_cap * sizeof(rt_final));
	}
	finals[nfinals].fn = fn;
	finals[nfinals++].val = val;
	rt_unlock(&finals_lock);
}

// a collection now: minor (0) or major (1), as OCaml's Gc.minor/full_major
void rt_gc_collect(int full) {
	collect(full, 0);
}

// calls the queued finalisers (an exception escapes when propagate is set,
// as from OCaml's Gc.full_major; otherwise, at an allocation, it is reported)
void rt_gc_run_finalisers(int propagate) { run_finalisers(propagate); }

static void run_finalisers(int propagate) {
	if (finals_running) return;
	finals_running = 1;
	for (;;) {
		rt_lock(&finals_lock);
		if (final_qhead >= final_qlen) {
			rt_unlock(&finals_lock);
			break;
		}
		void **r = rt_push(2);
		r[0] = final_queue[final_qhead].fn;
		r[1] = final_queue[final_qhead].val;
		if (++final_qhead == final_qlen) final_qhead = final_qlen = 0;
		rt_unlock(&finals_lock);
		void *args = hx_arr_new(AK_PTR, 0);
		RT_ROOT(args);
		hx_apush_slow(args_root, AK_PTR, (uint64_t)(uintptr_t)&r[1]);
		RT_TRY(h)
			hx_dyn_call(r[0], *args_root);
		RT_CATCH(h)
			if (propagate) {
				finals_running = 0;
				rt_sp = r;
				rt_throw(rt_exn);
			}
			char *s = hx_str_to_utf8(hx_std_string(rt_exn));
			rt_exn = 0;
			fflush(stdout);
			fprintf(stderr, "Uncaught exception in a finaliser: %s\n", s);
			free(s);
		RT_END_TRY(h)
		rt_sp = r;
	}
	finals_running = 0;
}

// old objects whose every slot may hold a young pointer, scanned whole by the
// next minor collection (per thread, rt_mutator); a small cache drops
// repeated entries for one object
static void remember_obj(void *obj) {
	rt_mutator *m = rt_mut;
	size_t h = ((uintptr_t)obj >> 4) & 255;
	if (m->robjs_recent[h] == obj) return;
	m->robjs_recent[h] = obj;
	if (m->robjs_len == m->robjs_cap) {
		m->robjs_cap = m->robjs_cap ? m->robjs_cap * 2 : 256;
		m->robjs = (void **)realloc(m->robjs, m->robjs_cap * sizeof(void *));
	}
	m->robjs[m->robjs_len++] = obj;
}

void rt_write_barrier(void *obj, void **slot, void *val) {
	(void)obj;
	(void)val;
	rt_mutator *m = rt_mut;
	if (m->rem_len == m->rem_cap) {
		m->rem_cap = m->rem_cap ? m->rem_cap * 2 : 4096;
		m->rem = (void ***)realloc(m->rem, m->rem_cap * sizeof(void **));
	}
	m->rem[m->rem_len++] = slot;
}

// after a bulk move or copy of references into obj (memmove in natives): the
// remembered set records slots, so every slot now holding a young pointer is
// recorded again. A long range (e.g. Array.insert at the front of a large
// array, as the port does for OCaml's `x :: l`) remembers the whole object
// once instead: recording its slots made the set grow by the array's length
// at every insertion (16M entries, 128 MB, on the self-compile).
void rt_barrier_range(void *obj, void **from, int32_t n) {
	if (in_young(obj)) return;
	if (n > 16) {
		remember_obj(obj);
		return;
	}
	for (int32_t i = 0; i < n; i++)
		if (in_young(from[i])) rt_write_barrier(obj, &from[i], from[i]);
}

#ifdef RT_CENSUS_BUILD
static void census_now(const char *when) {
	rt_census_info gi;
	memset(&gi, 0, sizeof gi);
	gi.when = when;
	gi.young = minor_size;
	gi.old_used = old_ptr - old_start;
	gi.old_limit = old_end - old_start;
	for (int i = 0; i < 2; i++)
		gi.populated[i] = populated[cur_region ^ i] > regions[cur_region ^ i] ? (size_t)(populated[cur_region ^ i] - regions[cur_region ^ i]) : 0;
	gi.remembered = (rt_mut->rem_cap + rt_mut->robjs_cap) * sizeof(void *); // the calling thread's
	gi.gcstack = gc_cap * sizeof(gc_frame);
	gi.shadow = (char *)rt_sp - (char *)rt_stack_base;
	gi.minors = minors;
	gi.majors = majors;
	gi.nglobals = nglobals;
	rt_census(old_start, old_ptr, &gi);
}
#endif

// RSS from /proc (Linux); 0 elsewhere
void rt_proc_rss(long *rss, long *hwm) {
	*rss = *hwm = 0;
	FILE *f = fopen("/proc/self/status", "r");
	if (!f) return;
	char line[256];
	while (fgets(line, sizeof line, f)) {
		if (!strncmp(line, "VmRSS:", 6)) *rss = atol(line + 6);
		if (!strncmp(line, "VmHWM:", 6)) *hwm = atol(line + 6);
	}
	fclose(f);
}

static void report(void) {
	if (stats) {
		long rss, hwm;
		rt_proc_rss(&rss, &hwm);
		fprintf(stderr, "gc: RSS %ld MB, peak %ld MB; old %zu MB used of %zu MB limit\n", rss >> 10, hwm >> 10, (size_t)(old_ptr - old_start) >> 20, (size_t)(old_end - old_start) >> 20);
	}
#ifdef RT_CENSUS_BUILD
	if (census) {
		int c = census;
		census = 0;
		major(0);
		census_now("exit");
		census = c;
	}
#endif
	if (stats) fprintf(stderr, "gc: %lu minor (%.2fs), %lu major (%.2fs), old %zu MB used\n", minors, minor_secs, majors, major_secs, (size_t)(old_ptr - old_start) >> 20);
}

#ifdef _WIN32
// The arguments as UTF-8, from the UTF-16 command line (OCaml's runtime on
// Windows does the same; main's argv is in the ANSI code page). The standard
// streams carry bytes as they are (haxe.ml: set_binary_mode_out; reads of
// descriptors are Unix.read's ReadFile, without the C runtime's text mode).
static void win_args(int *argc, char ***argv) {
	int n;
	wchar_t **w = CommandLineToArgvW(GetCommandLineW(), &n);
	if (!w) return;
	char **a = (char **)malloc(sizeof(char *) * (n + 1));
	for (int i = 0; i < n; i++) a[i] = rt_win_utf8(w[i]);
	a[n] = NULL;
	LocalFree(w);
	*argc = n;
	*argv = a;
}
#endif

void rt_init(int ng, int argc, char **argv) {
#ifdef _WIN32
	rt_win_init();
	win_args(&argc, &argv);
	_setmode(0, _O_BINARY);
	_setmode(1, _O_BINARY);
	_setmode(2, _O_BINARY);
#endif
	rt_argc = argc;
	rt_argv = argv;
	const char *m = getenv("RT_MINOR_KB");
	minor_size = (m ? (size_t)atoi(m) : 4096) << 10;
	minor_fixed = m != NULL;
	stats = getenv("RT_STATS") != NULL;
	const char *ah = getenv("RT_AHEAD_MB");
	if (ah) populate_ahead = (size_t)atoi(ah) << 20;
#ifdef RT_CENSUS_BUILD
	const char *cs = getenv("RT_CENSUS");
	census = cs ? atoi(cs) : 0;
#endif
	const char *rp = getenv("RT_RELEASE");
	release_pages = rp ? atoi(rp) : 1;
	gc_bfs = getenv("RT_BFS") != NULL;
#ifdef MADV_HUGEPAGE
	// transparent huge pages for the heap: the old space grows by hundreds of
	// MB and is copied into fresh pages, so 4 KB page faults add up
	const char *hp = getenv("RT_HUGE");
	huge_pages = hp && atoi(hp); // opt-in: it costs more kernel time than it saves here
#endif
	rt_young_start = nursery_alloc(minor_size);
	rt_young_end = rt_young_start + minor_size;
	young_next = rt_young_start; // rt_young_ptr = rt_young_limit = NULL: the first allocation takes a TLAB
	young_dirty = rt_young_start; // fresh pages
	poison = getenv("RT_VERIFY") != NULL;
	if (poison) memset(rt_young_start, POISON, minor_size);
	const char *zk = getenv("RT_ZCHUNK_KB");
	zchunk = (zk ? (size_t)atoi(zk) : 32) << 10;
	if (zchunk < 4096) zchunk = 4096;
	const char *tk = getenv("RT_TLAB_KB");
	tlab_size = tk ? (size_t)atoi(tk) << 10 : minor_size / 16;
	if (tlab_size < 4096) tlab_size = 4096;
	const char *rm = getenv("RT_REGION_MB");
	if (rm) region_bytes = (size_t)atoi(rm) << 20;
	for (int i = 0; i < 2; i++) {
		regions[i] = mmap(NULL, REGION, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE, -1, 0);
		if (regions[i] == MAP_FAILED && region_bytes > ((size_t)512 << 20)) {
			if (i == 1) munmap(regions[0], REGION);
			region_bytes /= 2;
			i = -1;
			continue;
		}
		if (regions[i] == MAP_FAILED) {
			fputs("cannot reserve heap\n", stderr);
			exit(2);
		}
#ifdef MADV_HUGEPAGE
		if (huge_pages) madvise(regions[i], REGION, MADV_HUGEPAGE);
#endif
	}
	old_start = old_ptr = regions[0];
	const char *om = getenv("RT_OLD_MB");
	old_end = old_start + ((size_t)(om ? atoi(om) : 256) << 20); // fewer major collections early on
	if (old_end > old_start + REGION) old_end = old_start + REGION;
	size_t stack_slots = 16u << 20;
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
	rt_sp_hw = rt_sp;
	rt_threads_init();
	nglobals = ng;
	rt_globals = (void **)calloc(ng + 1, sizeof(void *));
	hx_boxes_init(); // hxmc.rt.Boxes: the static boxes
	for (int t = 0; t < rt_ntypes; t++) {
		rt_type_objs[2 * t] = MKHDR(1, K_RAW, T_TYPEOBJ);
		*(int32_t *)&rt_type_objs[2 * t + 1] = t;
	}
	atexit(report);
}

// binds a mutator to the calling thread's runtime state
void rt_mutator_bind(rt_mutator *m) {
	m->sp_ref = &rt_sp;
	m->hw_ref = &rt_sp_hw;
	m->base_ref = &rt_stack_base;
	m->exn_ref = &rt_exn;
	m->yptr_ref = &rt_young_ptr;
	m->ylim_ref = &rt_young_limit;
	m->yrlim_ref = &rt_young_rlimit;
	rt_mut = m;
}

// ---- exceptions

__attribute__((noreturn)) void rt_throw(void *v) {
	rt_exn = v;
	if (!rt_hcur) {
		char *s = hx_str_to_utf8(hx_std_string(v));
		fprintf(stderr, "Uncaught exception: %s\n", s);
		exit(1);
	}
	RT_LONGJMP(rt_hcur->buf);
}

__attribute__((noreturn)) void hx_throw_str(const char *msg) {
	rt_throw(hx_str_of_ascii(msg));
}

// ---- hxmc.NativeGc

void hxmc_NativeGc_finalise(void *fn, void *val) { rt_gc_finalise(fn, val); }
void hxmc_NativeGc_collect(int32_t full) { rt_gc_collect(full); }
void hxmc_NativeGc_runFinalisers(void) { rt_gc_run_finalisers(1); }

// ---- object sizes (the port's server/memory, in place of OCaml's Objsize):
// the bytes of the heap objects reachable from v, headers included, without
// entering the objects of the array `exclude`; reaching an object of the array
// `out` sets the flag hxmc_NativeGc_reached returns (and is not entered either).
// Objects outside the heap (static data) are neither counted nor entered.
static int objsize_reached;

typedef struct {
	void **keys;
	size_t cap, len;
} ptrset;

static size_t ptrset_slot(ptrset *s, void *p) {
	size_t h = ((uintptr_t)p >> 3) * 0x9E3779B97F4A7C15ull;
	size_t i = h & (s->cap - 1);
	while (s->keys[i] && s->keys[i] != p) i = (i + 1) & (s->cap - 1);
	return i;
}

// adds p; returns 0 if it was there already
static int ptrset_add(ptrset *s, void *p) {
	if (2 * (s->len + 1) > s->cap) {
		ptrset n = {(void **)calloc(s->cap * 2, sizeof(void *)), s->cap * 2, 0};
		for (size_t i = 0; i < s->cap; i++)
			if (s->keys[i]) {
				n.keys[ptrset_slot(&n, s->keys[i])] = s->keys[i];
				n.len++;
			}
		free(s->keys);
		*s = n;
	}
	size_t i = ptrset_slot(s, p);
	if (s->keys[i]) return 0;
	s->keys[i] = p;
	s->len++;
	return 1;
}

static int ptrset_has(ptrset *s, void *p) { return s->keys[ptrset_slot(s, p)] != NULL; }

static int in_heap(void *p) {
	return p && (in_young(p) || ((char *)p >= old_start && (char *)p < old_ptr));
}

static void ptrset_add_array(ptrset *s, void *a) {
	if (!a || ARR_KIND(a) != AK_PTR || !ARR_DATA(a)) return;
	for (int32_t i = 0; i < ARR_LEN(a); i++)
		if (FP(ARR_DATA(a), i)) ptrset_add(s, FP(ARR_DATA(a), i));
}

double hxmc_NativeGc_objsize(void *v, void *exclude, void *out) {
	ptrset seen = {(void **)calloc(1024, sizeof(void *)), 1024, 0};
	ptrset ex = {(void **)calloc(64, sizeof(void *)), 64, 0};
	ptrset outs = {(void **)calloc(64, sizeof(void *)), 64, 0};
	ptrset_add_array(&ex, exclude);
	ptrset_add_array(&outs, out);
	size_t sp = 0, cap = 1024;
	void **stack = (void **)malloc(cap * sizeof(void *));
	double bytes = 0;
	objsize_reached = 0;
	if (in_heap(v)) stack[sp++] = v;
	while (sp) {
		void *o = stack[--sp];
		if (ptrset_has(&ex, o)) continue;
		if (ptrset_has(&outs, o)) {
			objsize_reached = 1;
			continue;
		}
		if (!ptrset_add(&seen, o)) continue;
		bytes += obj_bytes(o);
		uint32_t n = NSLOTS(o);
		const uint64_t *pm = KIND(o) == K_OBJ ? rt_types[TINDEX(o)].ptrmap : NULL;
		for (uint32_t i = 0; i < n; i++) {
			if (KIND(o) == K_OBJ) {
				if (!pm || !((pm[i / 64] >> (i % 64)) & 1)) continue;
			} else if (KIND(o) != K_PARR)
				break;
			void *c = FP(o, i);
			if (!in_heap(c)) continue;
			if (sp == cap) stack = (void **)realloc(stack, (cap *= 2) * sizeof(void *));
			stack[sp++] = c;
		}
	}
	free(stack);
	free(seen.keys);
	free(ex.keys);
	free(outs.keys);
	return bytes;
}

int32_t hxmc_NativeGc_reached(void) { return objsize_reached; }

// the bytes the heap spaces take (in place of OCaml's Gc heap words)
double hxmc_NativeGc_heapBytes(void) {
	return (double)(old_end - old_start) + (double)(rt_young_end - rt_young_start);
}
