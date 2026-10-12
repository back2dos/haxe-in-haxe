// The hxc runtime: Array, Math, Date, Bytes, BytesBuffer,
// FPHelper natives; DEFLATE decompression (hxc.NativeZip).
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
