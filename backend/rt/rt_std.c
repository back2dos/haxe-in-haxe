// EXPERIMENTAL runtime for backend/: Array, Math, Date, Bytes, BytesBuffer,
// FPHelper natives.
#include "rt.h"
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <time.h>

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
	RT_ROOT(a);
	RT_ROOT(b);
	void *r = Array_copy(a);
	RT_ROOT(r);
	for (int32_t i = 0;; i++) {
		RT_RELOAD(b);
		if (i >= ARR_LEN(b)) break;
		void *v = aget_boxed(b, i);
		*rt_sp++ = v;
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
		*rt_sp++ = v;
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
		*rt_sp++ = m;
		hx_apush_slow(r_root, AK_PTR, (uint64_t)(uintptr_t)(rt_sp - 1));
		rt_sp--;
	}
	RT_RELOAD(r);
	RT_UNROOT(3);
	return r;
}

// ---- Math

double Math_NaN(void) { return NAN; }
double Math_POSITIVE_INFINITY(void) { return INFINITY; }
double Math_NEGATIVE_INFINITY(void) { return -INFINITY; }
double Math_PI(void) { return 3.141592653589793; }
double Math_abs(double x) { return fabs(x); }
double Math_acos(double x) { return acos(x); }
double Math_asin(double x) { return asin(x); }
double Math_atan(double x) { return atan(x); }
double Math_atan2(double y, double x) { return atan2(y, x); }
double Math_cos(double x) { return cos(x); }
double Math_sin(double x) { return sin(x); }
double Math_tan(double x) { return tan(x); }
double Math_exp(double x) { return exp(x); }
double Math_log(double x) { return log(x); }
double Math_sqrt(double x) { return sqrt(x); }
double Math_pow(double x, double y) { return pow(x, y); }
int32_t Math_floor(double x) { return hx_f2i(floor(x)); }
int32_t Math_ceil(double x) { return hx_f2i(ceil(x)); }
int32_t Math_round(double x) { return hx_f2i(floor(x + 0.5)); }
double Math_ffloor(double x) { return floor(x); }
double Math_fceil(double x) { return ceil(x); }
double Math_fround(double x) { return floor(x + 0.5); }
double Math_max(double a, double b) { return a != a || b != b ? NAN : a > b ? a : b; }
double Math_min(double a, double b) { return a != a || b != b ? NAN : a < b ? a : b; }
int32_t Math_isNaN(double x) { return x != x; }
int32_t Math_isFinite(double x) { return isfinite(x); }
double Math_random(void) { return (double)rand() / ((double)RAND_MAX + 1); }

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
