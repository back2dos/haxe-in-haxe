// The hxmc runtime: what remains in C of the dynamic operations (the rest
// is Haxe, hxmc/std/hxmc/rt/Dyn.hx): the table of field names (names seen
// only at run time are interned under a lock, outside the heap) and the
// publication of inline-cache entries with several threads (per-thread
// tables of immutable entries); Dyn fills the entries (rt_icache_fill).
#include "rt_gc.h"
#include <stdio.h>
#include <stdlib.h>

int32_t hx_str_utf8_into(void *s, char *buf);
void *hx_str_of_utf8(const char *c, int32_t n);
void rt_icache_fill(void *o, int32_t fid, rt_icache *c);

// Dyn.fid's cache of (hash, fid + 1) entries
uint64_t rt_fid_cache[4096];
// Dyn.objHash's seed (per thread)
RT_TLS void *rt_hash_seed;
// Net's last socket errno (per thread, as errno)
RT_TLS void *rt_net_errno;
// spin locks of the runtime's Haxe code (Net's resolver: 0)
uint32_t rt_spin[16];

// ---- field names: the generated table is sorted; names seen only at run time are appended

// Names added at run time live in chunks that never move, so a reader needs no
// lock for a name it got an id for; adding (and searching the added names)
// holds extra_lock.
#define EXTRA_CHUNK 1024
static char **extra_chunks[4096];
static int nextra;
static rt_lock_t extra_lock = RT_LOCK_INIT;

static const char *extra_name(int i) { return extra_chunks[i / EXTRA_CHUNK][i % EXTRA_CHUNK]; }

static int32_t find_static_name(const char *name) {
	int lo = 0, hi = rt_nfield_names - 1;
	while (lo <= hi) {
		int mid = (lo + hi) / 2;
		int c = strcmp(rt_field_names[mid], name);
		if (c == 0) return mid;
		if (c < 0) lo = mid + 1;
		else hi = mid - 1;
	}
	return -1;
}

// the added names by hash (open addressing; entries are index + 1), under extra_lock
static int32_t *extra_hash;
static uint32_t extra_cap; // a power of two, at least twice nextra

static uint32_t name_hash(const char *s) {
	uint32_t h = 2166136261u; // FNV-1a
	for (; *s; s++)
		h = (h ^ (uint8_t)*s) * 16777619u;
	return h;
}

static int32_t find_extra(const char *name) {
	if (!extra_cap) return -1;
	for (uint32_t i = name_hash(name) & (extra_cap - 1);; i = (i + 1) & (extra_cap - 1)) {
		int32_t e = extra_hash[i];
		if (!e) return -1;
		if (strcmp(extra_name(e - 1), name) == 0) return rt_nfield_names + e - 1;
	}
}

static void hash_extra(int32_t i) {
	uint32_t j = name_hash(extra_name(i)) & (extra_cap - 1);
	while (extra_hash[j])
		j = (j + 1) & (extra_cap - 1);
	extra_hash[j] = i + 1;
}

// after appending name nextra - 1
static void add_extra_hash(void) {
	if ((uint32_t)nextra * 2 > extra_cap) {
		free(extra_hash);
		extra_cap = extra_cap ? extra_cap * 2 : 1024;
		extra_hash = (int32_t *)calloc(extra_cap, sizeof(int32_t));
		for (int32_t i = 0; i < nextra; i++)
			hash_extra(i);
	} else hash_extra(nextra - 1);
}

int32_t hx_fid_c(const char *name) {
	int32_t f = find_static_name(name);
	if (f >= 0) return f;
	rt_lock(&extra_lock);
	f = find_extra(name);
	rt_unlock(&extra_lock);
	return f;
}

static int32_t intern(const char *name) {
	int32_t f = find_static_name(name);
	if (f >= 0) return f;
	rt_lock(&extra_lock);
	f = find_extra(name);
	if (f < 0) {
		int c = nextra / EXTRA_CHUNK;
		if (!extra_chunks[c]) extra_chunks[c] = (char **)malloc(EXTRA_CHUNK * sizeof(char *));
		extra_chunks[c][nextra % EXTRA_CHUNK] = strdup(name);
		f = rt_nfield_names + nextra++;
		add_extra_hash();
	}
	rt_unlock(&extra_lock);
	return f;
}

int32_t hx_fid_slow(void *name) {
	char small[256];
	char *buf = STR_LEN(name) * 3 + 1 <= (int32_t)sizeof small ? small : (char *)malloc(STR_LEN(name) * 3 + 1);
	hx_str_utf8_into(name, buf);
	int32_t f = intern(buf);
	if (buf != small) free(buf);
	return f;
}

// the id of a name if it has one (no interning): -1 otherwise
int32_t hx_fid_find(void *name) {
	char small[256];
	char *buf = STR_LEN(name) * 3 + 1 <= (int32_t)sizeof small ? small : (char *)malloc(STR_LEN(name) * 3 + 1);
	hx_str_utf8_into(name, buf);
	int32_t f = hx_fid_c(buf);
	if (buf != small) free(buf);
	return f;
}

const char *hx_fid_name(int32_t f) {
	return f < rt_nfield_names ? rt_field_names[f] : extra_name(f - rt_nfield_names);
}

// a field name as a String, made once: an immortal copy outside the heap,
// laid out like the string literals (the collector leaves both alone)
static void **fid_strs;
static int32_t fid_strs_cap;

void *hx_fid_str(int32_t f) {
	rt_lock(&extra_lock);
	void *r = f < fid_strs_cap ? fid_strs[f] : NULL;
	rt_unlock(&extra_lock);
	if (r) return r;
	void *s = hx_str_of_utf8(hx_fid_name(f), (int32_t)strlen(hx_fid_name(f)));
	size_t bytes = 8 + 8 * (size_t)NSLOTS(s);
	char *copy = (char *)malloc(bytes);
	memcpy(copy, (char *)s - 8, bytes);
	r = copy + 8;
	rt_lock(&extra_lock);
	if (f >= fid_strs_cap) {
		int32_t ncap = fid_strs_cap ? fid_strs_cap : 1024;
		while (ncap <= f)
			ncap *= 2;
		fid_strs = (void **)realloc(fid_strs, ncap * sizeof(void *));
		memset(fid_strs + fid_strs_cap, 0, (ncap - fid_strs_cap) * sizeof(void *));
		fid_strs_cap = ncap;
	}
	if (fid_strs[f]) {
		free(copy);
		r = fid_strs[f];
	} else fid_strs[f] = r;
	rt_unlock(&extra_lock);
	return r;
}

// ---- inline caches

#if RT_MT
// Misses on entries filled for another type, with several threads: per
// thread, a table of immutable entries by (type, field id). A generated
// access may read its entry after evaluating arguments that miss again, so
// an entry, once returned, never changes.
typedef struct {
	uint64_t *keys; // type << 32 | fid, 0: free
	rt_icache **vals;
	uint32_t cap, n;
} ic_table;
static RT_TLS ic_table ic_local;

static rt_icache *ic_local_get(void *o, int32_t fid) {
	ic_table *tb = &ic_local;
	uint64_t key = (uint64_t)TINDEX(o) << 32 | (uint32_t)fid;
	if (tb->n * 2 >= tb->cap) {
		uint32_t ncap = tb->cap ? tb->cap * 2 : 256;
		uint64_t *nk = (uint64_t *)calloc(ncap, sizeof(uint64_t));
		rt_icache **nv = (rt_icache **)calloc(ncap, sizeof(rt_icache *));
		for (uint32_t i = 0; i < tb->cap; i++)
			if (tb->keys[i]) {
				uint32_t j = (uint32_t)((tb->keys[i] * 0x9E3779B97F4A7C15ull) >> 32) & (ncap - 1);
				while (nk[j]) j = (j + 1) & (ncap - 1);
				nk[j] = tb->keys[i];
				nv[j] = tb->vals[i];
			}
		free(tb->keys);
		free(tb->vals);
		tb->keys = nk;
		tb->vals = nv;
		tb->cap = ncap;
	}
	uint32_t j = (uint32_t)((key * 0x9E3779B97F4A7C15ull) >> 32) & (tb->cap - 1);
	while (tb->keys[j]) {
		if (tb->keys[j] == key) return tb->vals[j];
		j = (j + 1) & (tb->cap - 1);
	}
	rt_icache *e = (rt_icache *)malloc(sizeof(rt_icache));
	rt_icache_fill(o, fid, e);
	e->t = TINDEX(o);
	tb->keys[j] = key;
	tb->vals[j] = e;
	tb->n++;
	return e;
}
#endif

void rt_dyn_thread_exit(void) {
#if RT_MT
	ic_table *tb = &ic_local;
	for (uint32_t i = 0; i < tb->cap; i++)
		if (tb->keys[i]) free(tb->vals[i]);
	free(tb->keys);
	free(tb->vals);
	memset(tb, 0, sizeof *tb);
#endif
}

rt_icache *rt_icache_miss(void *o, int32_t fid, rt_icache *c) {
#if RT_MT
	if (rt_mt) {
		uint32_t z = 0;
		if (__atomic_compare_exchange_n(&c->t, &z, RT_IC_BUSY, 0, __ATOMIC_ACQUIRE, __ATOMIC_RELAXED)) {
			rt_icache_fill(o, fid, c);
			__atomic_store_n(&c->t, TINDEX(o), __ATOMIC_RELEASE);
			return c;
		}
		return ic_local_get(o, fid);
	}
#endif
	rt_icache_fill(o, fid, c);
	c->t = TINDEX(o);
	return c;
}

