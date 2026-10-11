// EXPERIMENTAL runtime for the C output of hxc/; see rt.h.
// RT_CENSUS=1: a heap census at exit (after a major collection, so only live
// objects are counted); RT_CENSUS=2 also after every major collection.
// Reports live bytes and object counts per type, what the same data would
// take in OCaml's representation (an estimate), where arrays, strings and
// maps hang from (the first object referring to them, by type and field),
// the heap's own sizes, malloc'd memory and the process's RSS.
#include "rt.h"
#include <stdio.h>
#include <stdlib.h>
#if defined(__GLIBC__) && !defined(__COSMOPOLITAN__)
#include <malloc.h>
#endif

typedef struct {
	uint64_t count, bytes, ocaml;
} cstat;

typedef struct {
	uint32_t src, fid; // referring type and field (fid -1: array data element)
	uint64_t count, bytes;
	uint32_t ttype; // referred type
} cattr;

static int cmp_stat_bytes(const void *a, const void *b) {
	uint64_t x = ((const cstat *)a)->bytes, y = ((const cstat *)b)->bytes;
	return x < y ? 1 : x > y ? -1 : 0;
}

static const char *fname(int32_t fid) {
	return fid >= 0 && fid < rt_nfield_names ? rt_field_names[fid] : "?";
}

// a type's display name: anonymous structures list their fields
static void tname(uint32_t t, char *buf, size_t n) {
	const rt_type *ty = &rt_types[t];
	if (ty->tk == TK_ANON) {
		size_t k = (size_t)snprintf(buf, n, "{");
		for (uint32_t i = 0; i < ty->nfields && k < n; i++)
			k += (size_t)snprintf(buf + k, n - k, "%s%s", i ? "," : "", fname(ty->fields[i].fid));
		if (k < n) snprintf(buf + k, n - k, "}");
	} else if (ty->tk == TK_CTOR && ty->super >= 0)
		snprintf(buf, n, "%s.%s", rt_types[ty->super].name, ty->name);
	else if (t == T_ADATA_P)
		snprintf(buf, n, "ArrayData<ptr>");
	else if (t == T_ADATA_RAW)
		snprintf(buf, n, "ArrayData<raw>");
	else if (t == T_REFBOX_P || t == T_REFBOX_I || t == T_REFBOX_F)
		snprintf(buf, n, "Ref<%c>", t == T_REFBOX_P ? 'p' : t == T_REFBOX_I ? 'i' : 'f');
	else
		snprintf(buf, n, "%s", ty->name);
}

static uint8_t *map_types; // per type: 1 for the haxe.ds maps
static int is_map(uint32_t t) { return map_types[t]; }
static void find_maps(void) {
	map_types = (uint8_t *)calloc(rt_ntypes, 1);
	for (int t = T_FIRST; t < rt_ntypes; t++) {
		const char *n = rt_types[t].name;
		map_types[t] = rt_types[t].tk == TK_CLASS && n && (!strcmp(n, "haxe.ds.StringMap") || !strcmp(n, "haxe.ds.IntMap") || !strcmp(n, "haxe.ds.ObjectMap"));
	}
}

static inline uint64_t r8(uint64_t n) { return (n + 7) & ~(uint64_t)7; }

static uint64_t obj_size(void *o) { return 8 * (uint64_t)(NSLOTS(o) + 1); }

// bytes of an object and what it owns exclusively in our layout: arrays with
// their data, maps with their arrays
static uint64_t deep(void *o) {
	if (!o) return 0;
	uint32_t t = TINDEX(o);
	uint64_t b = obj_size(o);
	if (t == T_ARRAY) {
		if (ARR_DATA(o)) b += obj_size(ARR_DATA(o));
	} else if (KIND(o) == K_OBJ && is_map(t)) {
		const rt_type *ty = &rt_types[t];
		for (uint32_t i = 0; i < ty->nfields; i++)
			if (ty->fields[i].kind == 'p') b += deep(FP(o, ty->fields[i].slot));
	}
	return b;
}

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

static int cmp_attr(const void *a, const void *b) {
	uint64_t x = ((const cattr *)a)->bytes, y = ((const cattr *)b)->bytes;
	return x < y ? 1 : x > y ? -1 : 0;
}

void rt_census(char *start, char *end, const rt_census_info *gi) {
	FILE *out = stderr;
	if (!map_types) find_maps();
	int top = 40;
	const char *e = getenv("RT_CENSUS_TOP");
	if (e) top = atoi(e);
	cstat *ts = (cstat *)calloc(rt_ntypes, sizeof(cstat));
	uint64_t total = 0, objs = 0, ocaml = 0;
	// strings
	uint64_t s_n = 0, s_bytes = 0, s_latin1 = 0, s_units = 0, s_bytes1 = 0, s_ocaml = 0, s_empty = 0;
	uint64_t s_hist[8] = {0}; // length buckets: 0, 1-7, 8-15, 16-31, 32-63, 64-255, 256+
	// arrays
	uint64_t a_n = 0, a_nodata = 0, a_len0 = 0, a_len = 0, a_cap = 0, a_waste = 0, a_hdr = 0, a_data = 0, a_ocaml = 0;
	uint64_t a_hist[8] = {0}; // length buckets: 0, 1, 2, 3-4, 5-8, 9-16, 17-64, 65+
	// enum values, anonymous objects, classes
	uint64_t c_n = 0, c_bytes = 0, an_n = 0, an_ovf = 0, cl_n = 0, cl_bytes = 0, k_ib = 0, k_obj = 0, k_nullp = 0, k_ptrs = 0;
	uint64_t boxes[3] = {0};
	// a string census by content, for duplicates
	size_t hcap = 1 << 20;
	void **hs = (void **)calloc(hcap, sizeof(void *));
	uint64_t s_distinct = 0, s_dupbytes = 0;
	for (char *p = start; p < end;) {
		void *o = p + 8;
		uint32_t t = TINDEX(o), k = KIND(o);
		uint64_t b = obj_size(o), oc = b;
		p += b;
		objs++;
		total += b;
		if (t >= (uint32_t)rt_ntypes) t = 0;
		const rt_type *ty = &rt_types[t];
		if (t == T_STRING) {
			int32_t len = STR_LEN(o);
			const uint16_t *u = STR_CHARS(o);
			int lat = 1;
			for (int32_t i = 0; i < len; i++)
				if (u[i] > 0xFF) {
					lat = 0;
					break;
				}
			s_n++;
			s_bytes += b;
			s_units += len;
			if (!len) s_empty++;
			if (lat) s_latin1++;
			s_bytes1 += 8 + 8 + r8(lat ? len : 2 * (uint64_t)len);
			oc = 8 + r8((uint64_t)len + 1); // UTF-8 for non-Latin-1: about as many bytes
			s_ocaml += oc;
			int hb = len == 0 ? 0 : len < 8 ? 1 : len < 16 ? 2 : len < 32 ? 3 : len < 64 ? 4 : len < 256 ? 5 : 6;
			s_hist[hb]++;
			uint32_t h = 2166136261u;
			for (int32_t i = 0; i < len; i++)
				h = (h ^ u[i]) * 16777619u;
			if (s_distinct * 2 < hcap) {
				size_t j = h & (hcap - 1);
				for (;;) {
					if (!hs[j]) {
						hs[j] = o;
						s_distinct++;
						break;
					}
					if (STR_LEN(hs[j]) == len && !memcmp(STR_CHARS(hs[j]), u, 2 * (size_t)len)) {
						s_dupbytes += b;
						break;
					}
					j = (j + 1) & (hcap - 1);
				}
			}
		} else if (t == T_ARRAY && k == K_OBJ) {
			int32_t len = ARR_LEN(o), cap = ARR_CAP(o);
			void *d = ARR_DATA(o);
			int es = ARR_KIND(o) == AK_I32 ? 4 : 8;
			a_n++;
			a_hdr += b;
			if (!d) a_nodata++;
			if (!len) a_len0++;
			a_len += len;
			if (d) {
				a_cap += cap;
				a_waste += (uint64_t)(cap - len) * es;
			}
			int hb = len == 0 ? 0 : len == 1 ? 1 : len == 2 ? 2 : len <= 4 ? 3 : len <= 8 ? 4 : len <= 16 ? 5 : len <= 64 ? 6 : 7;
			a_hist[hb]++;
			// OCaml: an array (header + elements; ints and floats unboxed)
			oc = len ? 8 + 8 * (uint64_t)len : 0;
			a_ocaml += oc;
		} else if (t == T_ADATA_P || t == T_ADATA_RAW) {
			a_data += b;
			oc = 0; // counted with the array
		} else if (t == T_BOXINT || t == T_BOXBOOL) {
			boxes[0]++;
			oc = 0; // immediate
		} else if (t == T_BOXFLOAT) {
			boxes[1]++;
		} else if (k == K_OBJ && ty->tk == TK_CTOR) {
			c_n++;
			c_bytes += b; // as in OCaml: the tag is the header's type index
		} else if (k == K_OBJ && ty->tk == TK_ANON) {
			an_n++;
			if (FP(o, 0)) an_ovf++;
			oc = 8 + 8 * (uint64_t)ty->nfields; // a record: a word per field, no overflow slot
		} else if (k == K_OBJ && ty->tk == TK_CLASS) {
			oc = 8 + 8 * (uint64_t)(ty->nfields ? ty->nfields : 1); // a word per field (Int/Bool are packed here)
		} else if (k == K_OBJ && ty->tk == TK_CLOSURE) {
			cl_n++;
			cl_bytes += b;
			oc = b + 8; // code pointer, closure info, environment
		}
		if (k == K_OBJ && t >= T_FIRST && (ty->tk == TK_CLASS || ty->tk == TK_CTOR || ty->tk == TK_ANON)) {
			k_obj++;
			for (uint32_t i = 0; i < ty->nfields; i++) {
				char fk = ty->fields[i].kind;
				if (fk == 'i' || fk == 'b') k_ib++;
				else if (fk == 'p') {
					k_ptrs++;
					if (!FP(o, ty->fields[i].slot)) k_nullp++;
				}
			}
		}
		ts[t].count++;
		ts[t].bytes += b;
		ts[t].ocaml += oc;
		ocaml += oc;
	}
	// first-referrer attribution of arrays, strings and maps
	size_t nattr = 0, attr_cap = 1 << 16;
	cattr *attr = (cattr *)calloc(attr_cap, sizeof(cattr));
	size_t words = (size_t)(end - start) / 8;
	uint8_t *seen = (uint8_t *)calloc(words / 8 + 1, 1);
#define SEEN(o) ((seen[(((char *)(o) - start) / 8) >> 3] >> ((((char *)(o) - start) / 8) & 7)) & 1)
#define MARK(o) (seen[(((char *)(o) - start) / 8) >> 3] |= 1 << ((((char *)(o) - start) / 8) & 7))
	for (char *p = start; p < end;) {
		void *o = p + 8;
		uint32_t t = TINDEX(o), k = KIND(o);
		p += obj_size(o);
		if (k != K_OBJ || t < T_FIRST || t >= (uint32_t)rt_ntypes) continue;
		const rt_type *ty = &rt_types[t];
		if (is_map(t)) continue; // a map's own arrays are counted with it
		for (uint32_t i = 0; i < ty->nfields; i++) {
			if (ty->fields[i].kind != 'p') continue;
			void *v = FP(o, ty->fields[i].slot);
			if (!v || (char *)v < start || (char *)v >= end || SEEN(v)) continue;
			uint32_t vt = TINDEX(v);
			if (!(vt == T_ARRAY || vt == T_STRING || (KIND(v) == K_OBJ && is_map(vt)))) continue;
			MARK(v);
			uint64_t b = deep(v);
			size_t j = 0;
			for (; j < nattr; j++)
				if (attr[j].src == t && attr[j].fid == (uint32_t)ty->fields[i].fid) break;
			if (j == nattr) {
				if (nattr == attr_cap) continue;
				attr[nattr].src = t;
				attr[nattr].fid = ty->fields[i].fid;
				attr[nattr].ttype = vt;
				nattr++;
			}
			attr[j].count++;
			attr[j].bytes += b;
		}
	}
	long rss, hwm;
	rt_proc_rss(&rss, &hwm);
	fprintf(out, "census (%s): %llu objects, %.1f MB live; OCaml representation estimate %.1f MB\n", gi->when, (unsigned long long)objs, total / 1048576.0, ocaml / 1048576.0);
	fprintf(out, "  heap: young %.1f MB, old %.1f MB used of %.1f MB limit, old reserve populated %.1f + %.1f MB (to/from), %lu minor, %lu major\n", gi->young / 1048576.0, gi->old_used / 1048576.0, gi->old_limit / 1048576.0, gi->populated[0] / 1048576.0, gi->populated[1] / 1048576.0, gi->minors, gi->majors);
	fprintf(out, "  other: remembered set %.1f MB, gc stack %.1f MB, shadow stack used %.1f MB, globals %d\n", gi->remembered / 1048576.0, gi->gcstack / 1048576.0, gi->shadow / 1048576.0, gi->nglobals);
#if defined(__GLIBC__) && !defined(__COSMOPOLITAN__) && (__GLIBC__ > 2 || (__GLIBC__ == 2 && __GLIBC_MINOR__ >= 33))
	struct mallinfo2 mi = mallinfo2();
	fprintf(out, "  malloc: %.1f MB in use (arena %.1f MB, mmap %.1f MB)\n", (mi.uordblks + mi.hblkhd) / 1048576.0, mi.arena / 1048576.0, mi.hblkhd / 1048576.0);
#endif
	fprintf(out, "  process: RSS %.1f MB, peak RSS %.1f MB\n", rss / 1024.0, hwm / 1024.0);
	fprintf(out, "  strings: %llu (%llu empty), %.1f MB, %llu units, %.1f%% Latin-1; 1-byte Latin-1 would be %.1f MB; OCaml %.1f MB; %llu distinct (duplicates %.1f MB)\n", (unsigned long long)s_n, (unsigned long long)s_empty, s_bytes / 1048576.0, (unsigned long long)s_units, s_n ? 100.0 * s_latin1 / s_n : 0, s_bytes1 / 1048576.0, s_ocaml / 1048576.0, (unsigned long long)s_distinct, s_dupbytes / 1048576.0);
	fprintf(out, "    length 0:%llu 1-7:%llu 8-15:%llu 16-31:%llu 32-63:%llu 64-255:%llu 256+:%llu\n", (unsigned long long)s_hist[0], (unsigned long long)s_hist[1], (unsigned long long)s_hist[2], (unsigned long long)s_hist[3], (unsigned long long)s_hist[4], (unsigned long long)s_hist[5], (unsigned long long)s_hist[6]);
	fprintf(out, "  arrays: %llu (%llu without data, %llu empty), headers %.1f MB + data %.1f MB, %llu elements, capacity %llu (slack %.1f MB); OCaml arrays %.1f MB\n", (unsigned long long)a_n, (unsigned long long)a_nodata, (unsigned long long)a_len0, a_hdr / 1048576.0, a_data / 1048576.0, (unsigned long long)a_len, (unsigned long long)a_cap, a_waste / 1048576.0, a_ocaml / 1048576.0);
	fprintf(out, "    length 0:%llu 1:%llu 2:%llu 3-4:%llu 5-8:%llu 9-16:%llu 17-64:%llu 65+:%llu\n", (unsigned long long)a_hist[0], (unsigned long long)a_hist[1], (unsigned long long)a_hist[2], (unsigned long long)a_hist[3], (unsigned long long)a_hist[4], (unsigned long long)a_hist[5], (unsigned long long)a_hist[6], (unsigned long long)a_hist[7]);
	fprintf(out, "  enum values: %llu, %.1f MB; anonymous objects: %llu (%llu with overflow; the slot: %.1f MB); closures: %llu, %.1f MB\n", (unsigned long long)c_n, c_bytes / 1048576.0, (unsigned long long)an_n, (unsigned long long)an_ovf, an_n * 8 / 1048576.0, (unsigned long long)cl_n, cl_bytes / 1048576.0);
	fprintf(out, "  fields of %llu objects: %llu Int/Bool (%.1f MB as 4-byte values), %llu pointers (%llu null); boxes: %llu Int/Bool, %llu Float\n", (unsigned long long)k_obj, (unsigned long long)k_ib, k_ib * 4 / 1048576.0, (unsigned long long)k_ptrs, (unsigned long long)k_nullp, (unsigned long long)boxes[0], (unsigned long long)boxes[1]);
	// types by bytes
	typedef struct {
		cstat s;
		uint32_t t;
	} row;
	row *rows = (row *)malloc(rt_ntypes * sizeof(row));
	int nr = 0;
	for (int t = 0; t < rt_ntypes; t++)
		if (ts[t].count) {
			rows[nr].s = ts[t];
			rows[nr].t = t;
			nr++;
		}
	qsort(rows, nr, sizeof(row), cmp_stat_bytes);
	fprintf(out, "  %-56s %10s %9s %9s %7s\n", "type", "count", "MB", "OCaml MB", "B/obj");
	for (int i = 0; i < nr && i < top; i++) {
		char nb[200];
		tname(rows[i].t, nb, sizeof nb);
		fprintf(out, "  %-56.56s %10llu %9.2f %9.2f %7.1f\n", nb, (unsigned long long)rows[i].s.count, rows[i].s.bytes / 1048576.0, rows[i].s.ocaml / 1048576.0, (double)rows[i].s.bytes / rows[i].s.count);
	}
	qsort(attr, nattr, sizeof(cattr), cmp_attr);
	fprintf(out, "  arrays (with data), strings and maps (with their arrays) by first referrer:\n");
	for (size_t i = 0; i < nattr && (int)i < top; i++) {
		char nb[200], vb[64];
		tname(attr[i].src, nb, sizeof nb);
		tname(attr[i].ttype, vb, sizeof vb);
		char full[300];
		snprintf(full, sizeof full, "%s.%s (%s)", nb, fname(attr[i].fid), vb);
		fprintf(out, "  %-66.66s %10llu %9.2f\n", full, (unsigned long long)attr[i].count, attr[i].bytes / 1048576.0);
	}
	free(rows);
	free(attr);
	free(seen);
	free(hs);
	free(ts);
}
