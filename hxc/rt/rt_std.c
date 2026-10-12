// The hxc runtime: Array, Math, Date, Bytes, BytesBuffer,
// FPHelper natives; DEFLATE decompression (hxc.NativeZip).
#include "rt.h"
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <time.h>
#ifdef _WIN32
// the C runtime's reentrant forms; its rand() has 15 bits: two make 30
#define localtime_r(t, r) (localtime_s((r), (t)) == 0 ? (r) : NULL)
#define gmtime_r(t, r) (gmtime_s((r), (t)) == 0 ? (r) : NULL)
#define RT_RAND() ((rand() << 15) ^ rand())
#define RT_RAND_MAX 0x3FFFFFFF
#else
#define RT_RAND() rand()
#define RT_RAND_MAX RAND_MAX
#endif

void hx_arr_to_ptr(void **slot);
void *hx_str_alloc(int32_t len);
int32_t hx_str_utf8_into(void *s, char *buf);

// ---- Array (generic natives: T values are Dynamic, the array keeps its element kind)

static inline void *aget_boxed(void *a, int32_t i) { return hx_aget_p_slow(a, i); }

static int32_t elem_size(void *a) { return ARR_KIND(a) == AK_I32 ? 4 : 8; }

void *Array_copy(void *a) {
	int32_t n = ARR_LEN(a);
	RT_ROOT(a);
	void *r = hx_arr_new(ARR_KIND(a), n);
	RT_RELOAD(a);
	RT_UNROOT(1);
	if (ARR_DATA(r)) // empty arrays have no data
	memcpy(ARR_DATA(r), ARR_DATA(a), (size_t)elem_size(a) * n);
	if (ARR_KIND(r) == AK_PTR) rt_barrier_range(ARR_DATA(r), (void **)ARR_DATA(r), n);
	return r;
}

void *Array_concat(void *a, void *b) {
	if (ARR_KIND(a) == ARR_KIND(b)) {
		// same element kind: one allocation, two copies
		int32_t na = ARR_LEN(a), nb = ARR_LEN(b);
		RT_ROOT(a);
		RT_ROOT(b);
		void *r = hx_arr_new(ARR_KIND(a), na + nb);
		RT_RELOAD(a);
		RT_RELOAD(b);
		RT_UNROOT(2);
		if (na + nb > 0) {
			size_t es = (size_t)elem_size(a);
			memcpy(ARR_DATA(r), ARR_DATA(a), es * na);
			memcpy((char *)ARR_DATA(r) + es * na, ARR_DATA(b), es * nb);
			if (ARR_KIND(r) == AK_PTR) rt_barrier_range(ARR_DATA(r), (void **)ARR_DATA(r), na + nb);
		}
		return r;
	}
	RT_ROOT(a);
	RT_ROOT(b);
	void *r = Array_copy(a);
	RT_ROOT(r);
	for (int32_t i = 0;; i++) {
		RT_RELOAD(b);
		if (i >= ARR_LEN(b)) break;
		void *v = aget_boxed(b, i);
		*rt_push(1) = v;
		hx_apush_slow(r_root, AK_PTR, (uint64_t)(uintptr_t)(rt_sp - 1));
		rt_sp--;
	}
	RT_RELOAD(r);
	RT_UNROOT(3);
	return r;
}

static int32_t index_of(void *a, void *x, int32_t from) {
	int32_t n = ARR_LEN(a);
	if (from < 0) {
		from += n;
		if (from < 0) from = 0;
	}
	switch (ARR_KIND(a)) {
	case AK_I32: {
		if (x && TINDEX(x) == T_BOXFLOAT && FD(x, 0) != floor(FD(x, 0))) return -1;
		if (!x) return -1;
		int32_t v = hx_unbox_int(x);
		for (int32_t i = from; i < n; i++)
			if (((int32_t *)ARR_DATA(a))[i] == v) return i;
		return -1;
	}
	case AK_F64: {
		if (!x) return -1;
		double v = hx_unbox_float(x);
		for (int32_t i = from; i < n; i++)
			if (((double *)ARR_DATA(a))[i] == v) return i;
		return -1;
	}
	default:
		for (int32_t i = from; i < n; i++) {
			void *e = FP(ARR_DATA(a), i);
			if (e == x || hx_dyn_eq(e, x)) return i;
		}
		return -1;
	}
}

int32_t Array_indexOf(void *a, void *x, void *from) {
	return index_of(a, x, from ? hx_unbox_int(from) : 0);
}

int32_t Array_lastIndexOf(void *a, void *x, void *from) {
	int32_t n = ARR_LEN(a);
	int32_t f = from ? hx_unbox_int(from) : n - 1;
	if (f < 0) f += n;
	if (f >= n) f = n - 1;
	for (int32_t i = f; i >= 0; i--) {
		void *e = ARR_KIND(a) == AK_PTR ? FP(ARR_DATA(a), i) : 0;
		if (ARR_KIND(a) == AK_PTR ? (e == x || hx_dyn_eq(e, x)) : (x && hx_aget_f_slow(a, i) == hx_unbox_float(x))) return i;
	}
	return -1;
}

int32_t Array_contains(void *a, void *x) {
	return index_of(a, x, 0) >= 0;
}

// removes element i, shifting the rest down
static void remove_at(void *a, int32_t i) {
	int32_t n = ARR_LEN(a), es = elem_size(a);
	char *d = (char *)ARR_DATA(a);
	memmove(d + (size_t)es * i, d + (size_t)es * (i + 1), (size_t)es * (n - i - 1));
	memset(d + (size_t)es * (n - 1), 0, es);
	if (ARR_KIND(a) == AK_PTR) rt_barrier_range(d, (void **)d + i, n - i - 1);
	ARR_LEN(a) = n - 1;
}

int32_t Array_remove(void *a, void *x) {
	int32_t i = index_of(a, x, 0);
	if (i < 0) return 0;
	remove_at(a, i);
	return 1;
}

void *Array_pop(void *a) {
	int32_t n = ARR_LEN(a);
	if (n == 0) return 0;
	RT_ROOT(a);
	void *v = aget_boxed(a, n - 1);
	RT_RELOAD(a);
	RT_UNROOT(1);
	memset((char *)ARR_DATA(a) + (size_t)elem_size(a) * (n - 1), 0, elem_size(a));
	ARR_LEN(a) = n - 1;
	return v;
}

void *Array_shift(void *a) {
	if (ARR_LEN(a) == 0) return 0;
	RT_ROOT(a);
	void *v = aget_boxed(a, 0);
	RT_RELOAD(a);
	RT_UNROOT(1);
	remove_at(a, 0);
	return v;
}

void Array_insert(void *a, int32_t pos, void *x) {
	int32_t n = ARR_LEN(a);
	if (pos < 0) {
		pos += n;
		if (pos < 0) pos = 0;
	}
	if (pos > n) pos = n;
	RT_ROOT(a);
	RT_ROOT(x);
	// grows (and converts the kind if needed); the length may have changed
	// meanwhile (another green thread at the allocation)
	n = hx_apush_slow(a_root, AK_PTR, (uint64_t)(uintptr_t)x_root);
	if (pos > n) pos = n;
	RT_RELOAD(a);
	int32_t es = elem_size(a);
	char *d = (char *)ARR_DATA(a);
	char tmp[8];
	memcpy(tmp, d + (size_t)es * n, es);
	memmove(d + (size_t)es * (pos + 1), d + (size_t)es * pos, (size_t)es * (n - pos));
	memcpy(d + (size_t)es * pos, tmp, es);
	if (ARR_KIND(a) == AK_PTR) rt_barrier_range(d, (void **)d + pos, n - pos + 1);
	RT_UNROOT(2);
}

void Array_unshift(void *a, void *x) {
	Array_insert(a, 0, x);
}

void Array_resize(void *a, int32_t len) {
	int32_t n = ARR_LEN(a);
	if (len < n) {
		memset((char *)ARR_DATA(a) + (size_t)elem_size(a) * len, 0, (size_t)elem_size(a) * (n - len));
		ARR_LEN(a) = len;
		return;
	}
	RT_ROOT(a);
	hx_arr_grow(a_root, len);
	RT_RELOAD(a);
	RT_UNROOT(1);
	ARR_LEN(a) = len;
}

void Array_reverse(void *a) {
	int32_t n = ARR_LEN(a), es = elem_size(a);
	char *d = (char *)ARR_DATA(a);
	char t[8];
	for (int32_t i = 0, j = n - 1; i < j; i++, j--) {
		memcpy(t, d + (size_t)es * i, es);
		memcpy(d + (size_t)es * i, d + (size_t)es * j, es);
		memcpy(d + (size_t)es * j, t, es);
	}
	if (ARR_KIND(a) == AK_PTR) rt_barrier_range(d, (void **)d, n);
}

void *Array_slice(void *a, int32_t pos, void *endp) {
	int32_t n = ARR_LEN(a);
	int32_t end = endp ? hx_unbox_int(endp) : n;
	if (pos < 0) {
		pos += n;
		if (pos < 0) pos = 0;
	}
	if (end < 0) end += n;
	if (end > n) end = n;
	int32_t len = end > pos ? end - pos : 0;
	RT_ROOT(a);
	void *r = hx_arr_new(ARR_KIND(a), len);
	RT_RELOAD(a);
	RT_UNROOT(1);
	if (ARR_DATA(r)) // empty arrays have no data
	memcpy(ARR_DATA(r), (char *)ARR_DATA(a) + (size_t)elem_size(a) * pos, (size_t)elem_size(a) * len);
	if (ARR_KIND(r) == AK_PTR) rt_barrier_range(ARR_DATA(r), (void **)ARR_DATA(r), len);
	return r;
}

void *Array_splice(void *a, int32_t pos, int32_t len) {
	int32_t n = ARR_LEN(a);
	if (pos < 0) {
		pos += n;
		if (pos < 0) pos = 0;
	}
	if (pos > n) pos = n;
	if (len < 0) len = 0;
	if (pos + len > n) len = n - pos;
	RT_ROOT(a);
	void *r = hx_arr_new(ARR_KIND(a), len);
	RT_RELOAD(a);
	RT_UNROOT(1);
	int32_t es = elem_size(a);
	char *d = (char *)ARR_DATA(a);
	if (ARR_DATA(r)) // empty arrays have no data
	memcpy(ARR_DATA(r), d + (size_t)es * pos, (size_t)es * len);
	memmove(d + (size_t)es * pos, d + (size_t)es * (pos + len), (size_t)es * (n - pos - len));
	memset(d + (size_t)es * (n - len), 0, (size_t)es * len);
	ARR_LEN(a) = n - len;
	if (ARR_KIND(a) == AK_PTR) {
		rt_barrier_range(ARR_DATA(r), (void **)ARR_DATA(r), len);
		rt_barrier_range(d, (void **)d + pos, n - pos - len);
	}
	return r;
}

void *Array_join(void *a, void *sep) {
	extern void *StringBuf_new(void);
	extern void StringBuf_add(void *b, void *x);
	extern void *StringBuf_toString(void *b);
	RT_ROOT(a);
	RT_ROOT(sep);
	void *b = StringBuf_new();
	RT_ROOT(b);
	for (int32_t i = 0;; i++) {
		RT_RELOAD(a);
		if (i >= ARR_LEN(a)) break;
		if (i > 0) {
			RT_RELOAD(b);
			RT_RELOAD(sep);
			StringBuf_add(b, sep);
		}
		RT_RELOAD(a);
		void *v = aget_boxed(a, i);
		RT_RELOAD(b);
		StringBuf_add(b, v);
	}
	RT_RELOAD(b);
	RT_UNROOT(3);
	return StringBuf_toString(b);
}

void *Array_toString(void *a) {
	return hx_std_string(a);
}

// stable merge sort; the comparator may allocate (and move objects), so
// elements are read from rooted arrays after every call
static int32_t cmp_call(void *f, void *x, void *y) {
	return ((int32_t(*)(void *, void *, void *))CLOS_FN(f))(f, x, y);
}

void Array_sort(void *a, void *f) {
	int32_t n = ARR_LEN(a);
	if (n < 2) return;
	RT_ROOT(a);
	RT_ROOT(f);
	if (ARR_KIND(a) != AK_PTR) hx_arr_to_ptr(a_root);
	void *src = Array_copy(*a_root);
	RT_ROOT(src);
	void *dst = Array_copy(*a_root);
	RT_ROOT(dst);
	for (int32_t width = 1; width < n; width *= 2) {
		for (int32_t lo = 0; lo < n; lo += 2 * width) {
			int32_t mid = lo + width < n ? lo + width : n;
			int32_t hi = lo + 2 * width < n ? lo + 2 * width : n;
			int32_t i = lo, j = mid, k = lo;
			while (i < mid && j < hi) {
				RT_RELOAD(src);
				int32_t c = cmp_call(*f_root, FP(ARR_DATA(src), j), FP(ARR_DATA(src), i));
				RT_RELOAD(src);
				RT_RELOAD(dst);
				void *v = c < 0 ? FP(ARR_DATA(src), j++) : FP(ARR_DATA(src), i++);
				rt_set_ptr(ARR_DATA(dst), &FP(ARR_DATA(dst), k++), v);
			}
			RT_RELOAD(src);
			RT_RELOAD(dst);
			while (i < mid)
				rt_set_ptr(ARR_DATA(dst), &FP(ARR_DATA(dst), k++), FP(ARR_DATA(src), i++));
			while (j < hi)
				rt_set_ptr(ARR_DATA(dst), &FP(ARR_DATA(dst), k++), FP(ARR_DATA(src), j++));
		}
		void *t = *src_root;
		*src_root = *dst_root;
		*dst_root = t;
	}
	RT_RELOAD(src);
	RT_RELOAD(a);
	for (int32_t i = 0; i < n; i++)
		rt_set_ptr(ARR_DATA(a), &FP(ARR_DATA(a), i), FP(ARR_DATA(src), i));
	RT_UNROOT(4);
}

void *Array_filter(void *a, void *f) {
	RT_ROOT(a);
	RT_ROOT(f);
	void *r = hx_arr_new(ARR_KIND(a), 0);
	RT_ROOT(r);
	for (int32_t i = 0;; i++) {
		RT_RELOAD(a);
		if (i >= ARR_LEN(a)) break;
		void *v = aget_boxed(a, i);
		*rt_push(1) = v;
		RT_RELOAD(f);
		int32_t keep = ((int32_t(*)(void *, void *))CLOS_FN(f))(f, v);
		if (keep) hx_apush_slow(r_root, AK_PTR, (uint64_t)(uintptr_t)(rt_sp - 1));
		rt_sp--;
	}
	RT_RELOAD(r);
	RT_UNROOT(3);
	return r;
}

void *Array_map(void *a, void *f) {
	RT_ROOT(a);
	RT_ROOT(f);
	void *r = hx_arr_new(AK_PTR, 0);
	RT_ROOT(r);
	for (int32_t i = 0;; i++) {
		RT_RELOAD(a);
		if (i >= ARR_LEN(a)) break;
		void *v = aget_boxed(a, i);
		RT_RELOAD(f);
		void *m = ((void *(*)(void *, void *))CLOS_FN(f))(f, v);
		*rt_push(1) = m;
		hx_apush_slow(r_root, AK_PTR, (uint64_t)(uintptr_t)(rt_sp - 1));
		rt_sp--;
	}
	RT_RELOAD(r);
	RT_UNROOT(3);
	return r;
}

// ---- Math

// (NaN ... isFinite: static inline in rt.h)
double Math_random(void) { return (double)RT_RAND() / ((double)RT_RAND_MAX + 1); }

// ---- Date: T_NATIVE object, slot 0 = milliseconds since the epoch (double)

static void *date_of(double ms) {
	void *d = rt_alloc(1, T_NATIVE, K_RAW);
	FD(d, 0) = ms;
	return d;
}

void *Date_new(int32_t y, int32_t m, int32_t d, int32_t h, int32_t mi, int32_t s) {
	struct tm t;
	memset(&t, 0, sizeof t);
	t.tm_year = y - 1900;
	t.tm_mon = m;
	t.tm_mday = d;
	t.tm_hour = h;
	t.tm_min = mi;
	t.tm_sec = s;
	t.tm_isdst = -1;
	return date_of((double)mktime(&t) * 1000.0);
}

void *Date_now(void) {
	struct timespec ts;
	clock_gettime(CLOCK_REALTIME, &ts);
	return date_of(ts.tv_sec * 1000.0 + ts.tv_nsec / 1e6);
}

void *Date_fromTime(double t) { return date_of(t); }

// HxOverrides.strDate: "hh:mm:ss" (UTC time of day), "YYYY-MM-DD", "YYYY-MM-DD hh:mm:ss" (local)
void *Date_fromString(void *s) {
	char *c = hx_str_to_utf8(s);
	size_t n = strlen(c);
	int y, mo, d, h, mi, se;
	void *r = NULL;
	if (n == 8 && sscanf(c, "%d:%d:%d", &h, &mi, &se) == 3) r = date_of(((double)h * 3600 + mi * 60 + se) * 1000.0);
	else if (n == 10 && sscanf(c, "%d-%d-%d", &y, &mo, &d) == 3) r = Date_new(y, mo - 1, d, 0, 0, 0);
	else if (n == 19 && sscanf(c, "%d-%d-%d %d:%d:%d", &y, &mo, &d, &h, &mi, &se) == 6) r = Date_new(y, mo - 1, d, h, mi, se);
	if (!r) {
		char msg[96];
		snprintf(msg, sizeof msg, "Invalid date format : %.60s", c);
		free(c);
		hx_throw_str(msg);
	}
	free(c);
	return r;
}
double Date_getTime(void *d) { return FD(d, 0); }

static struct tm local_of(void *d) {
	time_t s = (time_t)floor(FD(d, 0) / 1000.0);
	struct tm t;
	localtime_r(&s, &t);
	return t;
}

static struct tm utc_of(void *d) {
	time_t s = (time_t)floor(FD(d, 0) / 1000.0);
	struct tm t;
	gmtime_r(&s, &t);
	return t;
}

int32_t Date_getFullYear(void *d) { return local_of(d).tm_year + 1900; }
int32_t Date_getMonth(void *d) { return local_of(d).tm_mon; }
int32_t Date_getDate(void *d) { return local_of(d).tm_mday; }
int32_t Date_getDay(void *d) { return local_of(d).tm_wday; }
int32_t Date_getHours(void *d) { return local_of(d).tm_hour; }
int32_t Date_getMinutes(void *d) { return local_of(d).tm_min; }
int32_t Date_getSeconds(void *d) { return local_of(d).tm_sec; }
int32_t Date_getUTCFullYear(void *d) { return utc_of(d).tm_year + 1900; }
int32_t Date_getUTCMonth(void *d) { return utc_of(d).tm_mon; }
int32_t Date_getUTCDate(void *d) { return utc_of(d).tm_mday; }
int32_t Date_getUTCDay(void *d) { return utc_of(d).tm_wday; }
int32_t Date_getUTCHours(void *d) { return utc_of(d).tm_hour; }
int32_t Date_getUTCMinutes(void *d) { return utc_of(d).tm_min; }
int32_t Date_getUTCSeconds(void *d) { return utc_of(d).tm_sec; }
int32_t Date_getTimezoneOffset(void *d) {
	struct tm l = local_of(d), u = utc_of(d);
	return (int32_t)((mktime(&u) - mktime(&l)) / 60);
}

void *Date_toString(void *d) {
	struct tm t = local_of(d);
	char buf[32];
	snprintf(buf, sizeof buf, "%04d-%02d-%02d %02d:%02d:%02d", t.tm_year + 1900, t.tm_mon + 1, t.tm_mday, t.tm_hour, t.tm_min, t.tm_sec);
	return hx_str_of_ascii(buf);
}

// ---- Bytes: K_RAW, int32 length, then the bytes from offset 8

#define BYTES_LEN(b) (((int32_t *)(b))[0])
#define BYTES_DATA(b) ((unsigned char *)(b) + 8)

void *haxe_io_Bytes_alloc(int32_t len) {
	void *b = rt_alloc((8 + (uint32_t)len + 7) / 8, T_BYTES, K_RAW);
	BYTES_LEN(b) = len;
	return b;
}

int32_t haxe_io_Bytes_get_length(void *b) { return BYTES_LEN(b); }
int32_t haxe_io_Bytes_get(void *b, int32_t pos) { return BYTES_DATA(b)[pos]; }
void haxe_io_Bytes_set(void *b, int32_t pos, int32_t v) { BYTES_DATA(b)[pos] = (unsigned char)v; }

void haxe_io_Bytes_blit(void *b, int32_t pos, void *src, int32_t srcpos, int32_t len) {
	if (pos < 0 || srcpos < 0 || len < 0 || pos + len > BYTES_LEN(b) || srcpos + len > BYTES_LEN(src)) hx_throw_str("OutsideBounds");
	memmove(BYTES_DATA(b) + pos, BYTES_DATA(src) + srcpos, len);
}

void haxe_io_Bytes_fill(void *b, int32_t pos, int32_t len, int32_t v) {
	memset(BYTES_DATA(b) + pos, v, len);
}

void *haxe_io_Bytes_sub(void *b, int32_t pos, int32_t len) {
	if (pos < 0 || len < 0 || pos + len > BYTES_LEN(b)) hx_throw_str("OutsideBounds");
	RT_ROOT(b);
	void *r = haxe_io_Bytes_alloc(len);
	RT_RELOAD(b);
	RT_UNROOT(1);
	memcpy(BYTES_DATA(r), BYTES_DATA(b) + pos, len);
	return r;
}

int32_t haxe_io_Bytes_compare(void *a, void *b) {
	int32_t na = BYTES_LEN(a), nb = BYTES_LEN(b);
	int c = memcmp(BYTES_DATA(a), BYTES_DATA(b), na < nb ? na : nb);
	return c != 0 ? c : na - nb;
}

int32_t haxe_io_Bytes_getUInt16(void *b, int32_t pos) { return BYTES_DATA(b)[pos] | (BYTES_DATA(b)[pos + 1] << 8); }
void haxe_io_Bytes_setUInt16(void *b, int32_t pos, int32_t v) {
	BYTES_DATA(b)[pos] = v;
	BYTES_DATA(b)[pos + 1] = v >> 8;
}
int32_t haxe_io_Bytes_getInt32(void *b, int32_t pos) {
	int32_t v;
	memcpy(&v, BYTES_DATA(b) + pos, 4);
	return v;
}
void haxe_io_Bytes_setInt32(void *b, int32_t pos, int32_t v) { memcpy(BYTES_DATA(b) + pos, &v, 4); }
double haxe_io_Bytes_getDouble(void *b, int32_t pos) {
	double v;
	memcpy(&v, BYTES_DATA(b) + pos, 8);
	return v;
}
void haxe_io_Bytes_setDouble(void *b, int32_t pos, double v) { memcpy(BYTES_DATA(b) + pos, &v, 8); }
double haxe_io_Bytes_getFloat(void *b, int32_t pos) {
	float v;
	memcpy(&v, BYTES_DATA(b) + pos, 4);
	return v;
}
void haxe_io_Bytes_setFloat(void *b, int32_t pos, double v) {
	float f = (float)v;
	memcpy(BYTES_DATA(b) + pos, &f, 4);
}

void *haxe_io_Bytes_getString(void *b, int32_t pos, int32_t len, void *encoding) {
	(void)encoding;
	if (pos < 0 || len < 0 || pos + len > BYTES_LEN(b)) hx_throw_str("OutsideBounds");
	// decoding allocates once at the end: copy the bytes out first
	char small[256];
	char *buf = len <= (int32_t)sizeof small ? small : (char *)malloc(len);
	memcpy(buf, BYTES_DATA(b) + pos, len);
	void *s = hx_str_of_utf8(buf, len);
	if (buf != small) free(buf);
	return s;
}

void *haxe_io_Bytes_toString(void *b) {
	return haxe_io_Bytes_getString(b, 0, BYTES_LEN(b), 0);
}

void *haxe_io_Bytes_ofString(void *s, void *encoding) {
	(void)encoding;
	char small[512];
	size_t cap = 3 * (size_t)STR_LEN(s) + 1;
	char *buf = cap <= sizeof small ? small : (char *)malloc(cap);
	int32_t n = hx_str_utf8_into(s, buf);
	void *b = haxe_io_Bytes_alloc(n);
	memcpy(BYTES_DATA(b), buf, n);
	if (buf != small) free(buf);
	return b;
}

void *haxe_io_Bytes_toHex(void *b) {
	static const char hex[] = "0123456789abcdef";
	int32_t n = BYTES_LEN(b);
	RT_ROOT(b);
	void *s = hx_str_alloc(2 * n);
	RT_RELOAD(b);
	RT_UNROOT(1);
	for (int32_t i = 0; i < n; i++) {
		STR_CHARS(s)[2 * i] = hex[BYTES_DATA(b)[i] >> 4];
		STR_CHARS(s)[2 * i + 1] = hex[BYTES_DATA(b)[i] & 15];
	}
	return s;
}

void *haxe_io_Bytes_ofHex(void *s) {
	int32_t n = STR_LEN(s) / 2;
	RT_ROOT(s);
	void *b = haxe_io_Bytes_alloc(n);
	RT_RELOAD(s);
	RT_UNROOT(1);
	for (int32_t i = 0; i < n; i++) {
		int v = 0;
		for (int k = 0; k < 2; k++) {
			uint16_t c = STR_CHARS(s)[2 * i + k];
			v = v * 16 + (c >= '0' && c <= '9' ? c - '0' : c >= 'a' && c <= 'f' ? c - 'a' + 10 : c >= 'A' && c <= 'F' ? c - 'A' + 10 : 0);
		}
		BYTES_DATA(b)[i] = v;
	}
	return b;
}

// ---- BytesBuffer: slot 0 length, slot 1 Bytes (capacity)

void *haxe_io_BytesBuffer_new(void) {
	void *bb = rt_alloc(2, T_BYTESBUFFER, K_OBJ);
	RT_ROOT(bb);
	void *d = haxe_io_Bytes_alloc(64);
	RT_RELOAD(bb);
	RT_UNROOT(1);
	rt_set_ptr(bb, &FP(bb, 1), d);
	return bb;
}

int32_t haxe_io_BytesBuffer_get_length(void *bb) { return FI(bb, 0); }

// makes room for n more bytes; returns the (possibly moved) buffer
static void *bb_reserve(void *bb, int32_t n) {
	int32_t len = FI(bb, 0);
	void *d = FP(bb, 1);
	if (len + n <= BYTES_LEN(d)) return bb;
	int32_t cap = BYTES_LEN(d) * 2;
	if (cap < len + n) cap = len + n;
	RT_ROOT(bb);
	void *nd = haxe_io_Bytes_alloc(cap);
	RT_RELOAD(bb);
	RT_UNROOT(1);
	memcpy(BYTES_DATA(nd), BYTES_DATA(FP(bb, 1)), len);
	rt_set_ptr(bb, &FP(bb, 1), nd);
	return bb;
}

void haxe_io_BytesBuffer_addByte(void *bb, int32_t v) {
	bb = bb_reserve(bb, 1);
	BYTES_DATA(FP(bb, 1))[FI(bb, 0)++] = (unsigned char)v;
}

void haxe_io_BytesBuffer_addBytes(void *bb, void *b, int32_t pos, int32_t len) {
	if (pos < 0 || len < 0 || pos + len > BYTES_LEN(b)) hx_throw_str("OutsideBounds");
	RT_ROOT(b);
	bb = bb_reserve(bb, len);
	RT_RELOAD(b);
	RT_UNROOT(1);
	memcpy(BYTES_DATA(FP(bb, 1)) + FI(bb, 0), BYTES_DATA(b) + pos, len);
	FI(bb, 0) += len;
}

void haxe_io_BytesBuffer_add(void *bb, void *b) {
	haxe_io_BytesBuffer_addBytes(bb, b, 0, BYTES_LEN(b));
}

void haxe_io_BytesBuffer_addString(void *bb, void *s, void *encoding) {
	RT_ROOT(bb);
	void *b = haxe_io_Bytes_ofString(s, encoding);
	RT_RELOAD(bb);
	RT_UNROOT(1);
	haxe_io_BytesBuffer_add(bb, b);
}

void haxe_io_BytesBuffer_addInt32(void *bb, int32_t v) {
	bb = bb_reserve(bb, 4);
	memcpy(BYTES_DATA(FP(bb, 1)) + FI(bb, 0), &v, 4);
	FI(bb, 0) += 4;
}

void haxe_io_BytesBuffer_addFloat(void *bb, double v) {
	float f = (float)v;
	bb = bb_reserve(bb, 4);
	memcpy(BYTES_DATA(FP(bb, 1)) + FI(bb, 0), &f, 4);
	FI(bb, 0) += 4;
}

void haxe_io_BytesBuffer_addDouble(void *bb, double v) {
	bb = bb_reserve(bb, 8);
	memcpy(BYTES_DATA(FP(bb, 1)) + FI(bb, 0), &v, 8);
	FI(bb, 0) += 8;
}

void *haxe_io_BytesBuffer_getBytes(void *bb) {
	return haxe_io_Bytes_sub(FP(bb, 1), 0, FI(bb, 0));
}

// ---- FPHelper

double haxe_io_FPHelper_i32ToFloat(int32_t i) {
	float f;
	memcpy(&f, &i, 4);
	return f;
}

int32_t haxe_io_FPHelper_floatToI32(double v) {
	float f = (float)v;
	int32_t i;
	memcpy(&i, &f, 4);
	return i;
}

double haxe_io_FPHelper_i64ToDouble(int32_t low, int32_t high) {
	uint64_t u = ((uint64_t)(uint32_t)high << 32) | (uint32_t)low;
	double d;
	memcpy(&d, &u, 8);
	return d;
}

int32_t haxe_io_FPHelper_doubleLow(double v) {
	uint64_t u;
	memcpy(&u, &v, 8);
	return (int32_t)(uint32_t)u;
}

int32_t haxe_io_FPHelper_doubleHigh(double v) {
	uint64_t u;
	memcpy(&u, &v, 8);
	return (int32_t)(u >> 32);
}

// ---- DEFLATE decompression (hxc.NativeZip): a canonical-Huffman decoder of
// RFC 1951 streams held whole in memory. Errors (invalid codes, the input
// running out, the output overflowing) set `err`, which every loop checks.

typedef struct {
	const unsigned char *in;
	size_t inlen, inpos;
	unsigned char *out;
	size_t outlen, outpos;
	uint32_t bitbuf;
	int bitcnt, err;
} infl_state;

typedef struct {
	short count[16]; // the number of codes of each length
	short symbol[288]; // the symbols in code order
} infl_huff;

static int infl_bits(infl_state *s, int need) {
	uint32_t val = s->bitbuf;
	while (s->bitcnt < need) {
		if (s->inpos == s->inlen) {
			s->err = 1;
			return 0;
		}
		val |= (uint32_t)s->in[s->inpos++] << s->bitcnt;
		s->bitcnt += 8;
	}
	s->bitbuf = need == 32 ? 0 : val >> need;
	s->bitcnt -= need;
	return (int)(val & ((1u << need) - 1));
}

static int infl_decode(infl_state *s, const infl_huff *h) {
	int code = 0, first = 0, index = 0;
	for (int len = 1; len <= 15; len++) {
		code |= infl_bits(s, 1);
		if (s->err) return -1;
		int count = h->count[len];
		if (code - count < first) return h->symbol[index + (code - first)];
		index += count;
		first += count;
		first <<= 1;
		code <<= 1;
	}
	s->err = 1; // no code of 15 bits or less matches
	return -1;
}

// 0 for a complete code, > 0 for an incomplete one, < 0 for an oversubscribed one
static int infl_construct(infl_huff *h, const short *length, int n) {
	short offs[16];
	for (int len = 0; len <= 15; len++) h->count[len] = 0;
	for (int sym = 0; sym < n; sym++) h->count[length[sym]]++;
	if (h->count[0] == n) return 0;
	int left = 1;
	for (int len = 1; len <= 15; len++) {
		left <<= 1;
		left -= h->count[len];
		if (left < 0) return left;
	}
	offs[1] = 0;
	for (int len = 1; len < 15; len++) offs[len + 1] = (short)(offs[len] + h->count[len]);
	for (int sym = 0; sym < n; sym++)
		if (length[sym] != 0) h->symbol[offs[length[sym]]++] = (short)sym;
	return left;
}

static const short infl_lbase[29] = {3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258};
static const short infl_lext[29] = {0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0};
static const short infl_dbase[30] = {1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577};
static const short infl_dext[30] = {0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13};

static void infl_codes(infl_state *s, const infl_huff *lencode, const infl_huff *distcode) {
	for (;;) {
		int symbol = infl_decode(s, lencode);
		if (s->err) return;
		if (symbol < 256) {
			if (s->outpos == s->outlen) {
				s->err = 1;
				return;
			}
			s->out[s->outpos++] = (unsigned char)symbol;
		} else if (symbol == 256) {
			return;
		} else {
			symbol -= 257;
			if (symbol >= 29) {
				s->err = 1;
				return;
			}
			size_t len = (size_t)(infl_lbase[symbol] + infl_bits(s, infl_lext[symbol]));
			symbol = infl_decode(s, distcode);
			if (s->err) return;
			if (symbol < 0 || symbol >= 30) {
				s->err = 1;
				return;
			}
			size_t dist = (size_t)(infl_dbase[symbol] + infl_bits(s, infl_dext[symbol]));
			if (s->err || dist > s->outpos || len > s->outlen - s->outpos) {
				s->err = 1;
				return;
			}
			unsigned char *p = s->out + s->outpos;
			const unsigned char *q = p - dist;
			for (size_t i = 0; i < len; i++) p[i] = q[i]; // overlapping copies repeat the pattern
			s->outpos += len;
		}
	}
}

static void infl_stored(infl_state *s) {
	s->bitbuf = 0; // skip to the next byte boundary
	s->bitcnt = 0;
	if (s->inlen - s->inpos < 4) {
		s->err = 1;
		return;
	}
	const unsigned char *p = s->in + s->inpos;
	size_t len = (size_t)p[0] | ((size_t)p[1] << 8);
	if (p[2] != (unsigned char)~p[0] || p[3] != (unsigned char)~p[1]) {
		s->err = 1;
		return;
	}
	s->inpos += 4;
	if (len > s->inlen - s->inpos || len > s->outlen - s->outpos) {
		s->err = 1;
		return;
	}
	memcpy(s->out + s->outpos, s->in + s->inpos, len);
	s->inpos += len;
	s->outpos += len;
}

static void infl_fixed(infl_state *s) {
	infl_huff lencode, distcode;
	short lengths[288];
	int sym = 0;
	for (; sym < 144; sym++) lengths[sym] = 8;
	for (; sym < 256; sym++) lengths[sym] = 9;
	for (; sym < 280; sym++) lengths[sym] = 7;
	for (; sym < 288; sym++) lengths[sym] = 8;
	infl_construct(&lencode, lengths, 288);
	for (sym = 0; sym < 30; sym++) lengths[sym] = 5;
	infl_construct(&distcode, lengths, 30);
	infl_codes(s, &lencode, &distcode);
}

static void infl_dynamic(infl_state *s) {
	static const short order[19] = {16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15};
	short lengths[320];
	infl_huff lencode, distcode;
	int nlen = infl_bits(s, 5) + 257;
	int ndist = infl_bits(s, 5) + 1;
	int ncode = infl_bits(s, 4) + 4;
	if (s->err || nlen > 286 || ndist > 30) {
		s->err = 1;
		return;
	}
	int index;
	for (index = 0; index < ncode; index++) lengths[order[index]] = (short)infl_bits(s, 3);
	for (; index < 19; index++) lengths[order[index]] = 0;
	if (s->err || infl_construct(&lencode, lengths, 19) != 0) { // the code length code must be complete
		s->err = 1;
		return;
	}
	index = 0;
	while (index < nlen + ndist) {
		int symbol = infl_decode(s, &lencode);
		if (s->err) return;
		if (symbol < 16) {
			lengths[index++] = (short)symbol;
		} else {
			short len = 0;
			if (symbol == 16) {
				if (index == 0) {
					s->err = 1;
					return;
				}
				len = lengths[index - 1];
				symbol = 3 + infl_bits(s, 2);
			} else if (symbol == 17) {
				symbol = 3 + infl_bits(s, 3);
			} else {
				symbol = 11 + infl_bits(s, 7);
			}
			if (s->err || index + symbol > nlen + ndist) {
				s->err = 1;
				return;
			}
			while (symbol--) lengths[index++] = len;
		}
	}
	if (lengths[256] == 0) { // no end-of-block code
		s->err = 1;
		return;
	}
	// an incomplete code is only allowed for a single length
	int left = infl_construct(&lencode, lengths, nlen);
	if (left < 0 || (left > 0 && nlen - lencode.count[0] != 1)) {
		s->err = 1;
		return;
	}
	left = infl_construct(&distcode, lengths + nlen, ndist);
	if (left < 0 || (left > 0 && ndist - distcode.count[0] != 1)) {
		s->err = 1;
		return;
	}
	infl_codes(s, &lencode, &distcode);
}

int32_t hxc_NativeZip_inflateRaw(void *src, int32_t srcPos, int32_t srcLen, void *dst, int32_t dstPos, int32_t dstLen) {
	if (srcPos < 0 || srcLen < 0 || srcPos + srcLen > BYTES_LEN(src) || dstPos < 0 || dstLen < 0 || dstPos + dstLen > BYTES_LEN(dst))
		hx_throw_str("OutsideBounds");
	// nothing below allocates: the buffers stay in place
	infl_state s = {BYTES_DATA(src) + srcPos, (size_t)srcLen, 0, BYTES_DATA(dst) + dstPos, (size_t)dstLen, 0, 0, 0, 0};
	int last;
	do {
		last = infl_bits(&s, 1);
		int type = infl_bits(&s, 2);
		if (s.err) return -1;
		if (type == 0) infl_stored(&s);
		else if (type == 1) infl_fixed(&s);
		else if (type == 2) infl_dynamic(&s);
		else return -1;
		if (s.err) return -1;
	} while (!last);
	return (int32_t)s.outpos;
}

// the CRC-32 table of the reflected polynomial 0xEDB88320 (zlib's crc32)
static const uint32_t crc32_table[256] = {
	0x00000000u, 0x77073096u, 0xee0e612cu, 0x990951bau, 0x076dc419u, 0x706af48fu,
	0xe963a535u, 0x9e6495a3u, 0x0edb8832u, 0x79dcb8a4u, 0xe0d5e91eu, 0x97d2d988u,
	0x09b64c2bu, 0x7eb17cbdu, 0xe7b82d07u, 0x90bf1d91u, 0x1db71064u, 0x6ab020f2u,
	0xf3b97148u, 0x84be41deu, 0x1adad47du, 0x6ddde4ebu, 0xf4d4b551u, 0x83d385c7u,
	0x136c9856u, 0x646ba8c0u, 0xfd62f97au, 0x8a65c9ecu, 0x14015c4fu, 0x63066cd9u,
	0xfa0f3d63u, 0x8d080df5u, 0x3b6e20c8u, 0x4c69105eu, 0xd56041e4u, 0xa2677172u,
	0x3c03e4d1u, 0x4b04d447u, 0xd20d85fdu, 0xa50ab56bu, 0x35b5a8fau, 0x42b2986cu,
	0xdbbbc9d6u, 0xacbcf940u, 0x32d86ce3u, 0x45df5c75u, 0xdcd60dcfu, 0xabd13d59u,
	0x26d930acu, 0x51de003au, 0xc8d75180u, 0xbfd06116u, 0x21b4f4b5u, 0x56b3c423u,
	0xcfba9599u, 0xb8bda50fu, 0x2802b89eu, 0x5f058808u, 0xc60cd9b2u, 0xb10be924u,
	0x2f6f7c87u, 0x58684c11u, 0xc1611dabu, 0xb6662d3du, 0x76dc4190u, 0x01db7106u,
	0x98d220bcu, 0xefd5102au, 0x71b18589u, 0x06b6b51fu, 0x9fbfe4a5u, 0xe8b8d433u,
	0x7807c9a2u, 0x0f00f934u, 0x9609a88eu, 0xe10e9818u, 0x7f6a0dbbu, 0x086d3d2du,
	0x91646c97u, 0xe6635c01u, 0x6b6b51f4u, 0x1c6c6162u, 0x856530d8u, 0xf262004eu,
	0x6c0695edu, 0x1b01a57bu, 0x8208f4c1u, 0xf50fc457u, 0x65b0d9c6u, 0x12b7e950u,
	0x8bbeb8eau, 0xfcb9887cu, 0x62dd1ddfu, 0x15da2d49u, 0x8cd37cf3u, 0xfbd44c65u,
	0x4db26158u, 0x3ab551ceu, 0xa3bc0074u, 0xd4bb30e2u, 0x4adfa541u, 0x3dd895d7u,
	0xa4d1c46du, 0xd3d6f4fbu, 0x4369e96au, 0x346ed9fcu, 0xad678846u, 0xda60b8d0u,
	0x44042d73u, 0x33031de5u, 0xaa0a4c5fu, 0xdd0d7cc9u, 0x5005713cu, 0x270241aau,
	0xbe0b1010u, 0xc90c2086u, 0x5768b525u, 0x206f85b3u, 0xb966d409u, 0xce61e49fu,
	0x5edef90eu, 0x29d9c998u, 0xb0d09822u, 0xc7d7a8b4u, 0x59b33d17u, 0x2eb40d81u,
	0xb7bd5c3bu, 0xc0ba6cadu, 0xedb88320u, 0x9abfb3b6u, 0x03b6e20cu, 0x74b1d29au,
	0xead54739u, 0x9dd277afu, 0x04db2615u, 0x73dc1683u, 0xe3630b12u, 0x94643b84u,
	0x0d6d6a3eu, 0x7a6a5aa8u, 0xe40ecf0bu, 0x9309ff9du, 0x0a00ae27u, 0x7d079eb1u,
	0xf00f9344u, 0x8708a3d2u, 0x1e01f268u, 0x6906c2feu, 0xf762575du, 0x806567cbu,
	0x196c3671u, 0x6e6b06e7u, 0xfed41b76u, 0x89d32be0u, 0x10da7a5au, 0x67dd4accu,
	0xf9b9df6fu, 0x8ebeeff9u, 0x17b7be43u, 0x60b08ed5u, 0xd6d6a3e8u, 0xa1d1937eu,
	0x38d8c2c4u, 0x4fdff252u, 0xd1bb67f1u, 0xa6bc5767u, 0x3fb506ddu, 0x48b2364bu,
	0xd80d2bdau, 0xaf0a1b4cu, 0x36034af6u, 0x41047a60u, 0xdf60efc3u, 0xa867df55u,
	0x316e8eefu, 0x4669be79u, 0xcb61b38cu, 0xbc66831au, 0x256fd2a0u, 0x5268e236u,
	0xcc0c7795u, 0xbb0b4703u, 0x220216b9u, 0x5505262fu, 0xc5ba3bbeu, 0xb2bd0b28u,
	0x2bb45a92u, 0x5cb36a04u, 0xc2d7ffa7u, 0xb5d0cf31u, 0x2cd99e8bu, 0x5bdeae1du,
	0x9b64c2b0u, 0xec63f226u, 0x756aa39cu, 0x026d930au, 0x9c0906a9u, 0xeb0e363fu,
	0x72076785u, 0x05005713u, 0x95bf4a82u, 0xe2b87a14u, 0x7bb12baeu, 0x0cb61b38u,
	0x92d28e9bu, 0xe5d5be0du, 0x7cdcefb7u, 0x0bdbdf21u, 0x86d3d2d4u, 0xf1d4e242u,
	0x68ddb3f8u, 0x1fda836eu, 0x81be16cdu, 0xf6b9265bu, 0x6fb077e1u, 0x18b74777u,
	0x88085ae6u, 0xff0f6a70u, 0x66063bcau, 0x11010b5cu, 0x8f659effu, 0xf862ae69u,
	0x616bffd3u, 0x166ccf45u, 0xa00ae278u, 0xd70dd2eeu, 0x4e048354u, 0x3903b3c2u,
	0xa7672661u, 0xd06016f7u, 0x4969474du, 0x3e6e77dbu, 0xaed16a4au, 0xd9d65adcu,
	0x40df0b66u, 0x37d83bf0u, 0xa9bcae53u, 0xdebb9ec5u, 0x47b2cf7fu, 0x30b5ffe9u,
	0xbdbdf21cu, 0xcabac28au, 0x53b39330u, 0x24b4a3a6u, 0xbad03605u, 0xcdd70693u,
	0x54de5729u, 0x23d967bfu, 0xb3667a2eu, 0xc4614ab8u, 0x5d681b02u, 0x2a6f2b94u,
	0xb40bbe37u, 0xc30c8ea1u, 0x5a05df1bu, 0x2d02ef8du,
};

int32_t hxc_NativeZip_crc32(void *b, int32_t pos, int32_t len) {
	if (pos < 0 || len < 0 || pos + len > BYTES_LEN(b)) hx_throw_str("OutsideBounds");
	const unsigned char *p = BYTES_DATA(b) + pos;
	uint32_t c = 0xFFFFFFFFu;
	for (int32_t i = 0; i < len; i++) c = crc32_table[(c ^ p[i]) & 0xFF] ^ (c >> 8);
	return (int32_t)(c ^ 0xFFFFFFFFu);
}
