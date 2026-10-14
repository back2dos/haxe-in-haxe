// The hxmc runtime: what remains in C of strings (the rest is Haxe,
// hxmc/std/hxmc/rt/Str.hx): the shortest round-trip formatting of doubles
// (printf and strtod of the C library) and Std.string of any value (moves
// to Haxe with rt_dyn.c).
#include "rt.h"
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

void *StringBuf_new(void);
void StringBuf_add(void *b, void *x);
void *StringBuf_toString(void *b);

static void sb_add_str(void *b, void *s) { StringBuf_add(b, s); }

// shortest representation that reads back as the same double, formatted like JavaScript
void hx_format_float(double v, char *out) {
	if (v != v) {
		strcpy(out, "NaN");
		return;
	}
	if (isinf(v)) {
		strcpy(out, v > 0 ? "Infinity" : "-Infinity");
		return;
	}
	if (v == 0) {
		strcpy(out, signbit(v) ? "-0" : "0");
		return;
	}
	char buf[40];
	int prec;
	for (prec = 1; prec <= 17; prec++) {
		snprintf(buf, sizeof buf, "%.*e", prec - 1, v);
		if (strtod(buf, NULL) == v) break;
	}
	// buf: [-]d.ddde[+-]xx ; digits and exponent
	char digits[24];
	int nd = 0, neg = 0, i = 0;
	if (buf[0] == '-') {
		neg = 1;
		i = 1;
	}
	for (; buf[i] && buf[i] != 'e'; i++)
		if (buf[i] != '.') digits[nd++] = buf[i];
	digits[nd] = 0;
	int exp = atoi(buf + i + 1);
	char *o = out;
	if (neg) *o++ = '-';
	if (exp >= 21 || exp < -6) {
		*o++ = digits[0];
		if (nd > 1) {
			*o++ = '.';
			memcpy(o, digits + 1, nd - 1);
			o += nd - 1;
		}
		o += sprintf(o, "e%c%d", exp < 0 ? '-' : '+', exp < 0 ? -exp : exp);
	} else if (exp >= 0) {
		for (int k = 0; k <= exp; k++)
			*o++ = k < nd ? digits[k] : '0';
		if (nd > exp + 1) {
			*o++ = '.';
			memcpy(o, digits + exp + 1, nd - exp - 1);
			o += nd - exp - 1;
		}
	} else {
		*o++ = '0';
		*o++ = '.';
		for (int k = 0; k < -exp - 1; k++)
			*o++ = '0';
		memcpy(o, digits, nd);
		o += nd;
	}
	*o = 0;
}

// ---- Std

void *Std_string(void *v) {
	return hx_std_string(v);
}

int32_t Std_isOfType(void *v, void *t) {
	return hx_is(v, t);
}

void *Std_downcast(void *v, void *t) {
	return hx_is(v, t) ? v : 0;
}

// ---- Std.string

void *hx_std_string(void *v) {
	if (!v) return hx_str_or_null(0);
	uint32_t t = TINDEX(v);
	switch (t) {
	case T_STRING: return v;
	case T_BOXINT: return hx_str_of_int(FI(v, 0));
	case T_BOXFLOAT: return hx_str_of_float(FD(v, 0));
	case T_BOXI64: return hx_str_of_i64(FL(v, 0));
	case T_BOXBOOL: return hx_str_of_bool(FI(v, 0));
	case T_TYPEOBJ: return hx_str_of_ascii(rt_types[FI(v, 0)].name);
	case T_ARRAY: {
		// [a,b,c]
		RT_ROOT(v);
		void *b = StringBuf_new();
		RT_ROOT(b);
		StringBuf_addChar(b, '[');
		for (int32_t i = 0;; i++) {
			RT_RELOAD(v);
			if (i >= ARR_LEN(v)) break;
			if (i > 0) {
				RT_RELOAD(b);
				StringBuf_addChar(b, ',');
				RT_RELOAD(v);
			}
			void *e = hx_aget_p_slow(v, i);
			void *s = hx_std_string(e);
			RT_RELOAD(b);
			sb_add_str(b, s);
		}
		RT_RELOAD(b);
		StringBuf_addChar(b, ']');
		RT_RELOAD(b);
		RT_UNROOT(2);
		return StringBuf_toString(b);
	}
	}
	if (t < T_FIRST) return hx_str_of_ascii(rt_types[t].name);
	const rt_type *ty = &rt_types[t];
	switch (ty->tk) {
	case TK_CTOR: {
		// Name(p1,p2)
		RT_ROOT(v);
		void *b = StringBuf_new();
		RT_ROOT(b);
		void *name = hx_str_of_ascii(ty->name);
		RT_RELOAD(b);
		sb_add_str(b, name);
		uint32_t np = ty->nslots;
		if (np > 0) {
			RT_RELOAD(b);
			StringBuf_addChar(b, '(');
			for (uint32_t i = 0; i < np; i++) {
				if (i > 0) {
					RT_RELOAD(b);
					StringBuf_addChar(b, ',');
				}
				RT_RELOAD(v);
				void *p = 0;
				char k = 'p';
				for (uint32_t f = 0; f < ty->nfields; f++)
					if (ty->fields[f].slot == (int32_t)(ty->fields[f].kind == 'i' || ty->fields[f].kind == 'b' ? 2 * i : i)) k = ty->fields[f].kind;
				switch (k) {
				case 'i': p = hx_box_int(FI(v, i)); break;
				case 'b': p = hx_box_bool(FI(v, i)); break;
				case 'f': p = hx_box_float(FD(v, i)); break;
				default: p = FP(v, i);
				}
				void *s = hx_std_string(p);
				RT_RELOAD(b);
				sb_add_str(b, s);
			}
			RT_RELOAD(b);
			StringBuf_addChar(b, ')');
		}
		RT_RELOAD(b);
		RT_UNROOT(2);
		return StringBuf_toString(b);
	}
	case TK_CLASS: {
		extern int32_t hx_fid_c(const char *name);
		int32_t f = hx_fid_c("toString");
		if (f >= 0)
			for (uint32_t i = 0; i < ty->nmethods; i++)
				if (ty->methods[i].fid == f) return ((void *(*)(void *))ty->methods[i].fn)(v);
		return hx_str_of_ascii(ty->name);
	}
	case TK_ANON: {
		extern void *hx_anon_to_string(void *o);
		return hx_anon_to_string(v);
	}
	case TK_CLOSURE:
	case TK_BOUND: return hx_str_of_ascii("<function>");
	default: return hx_str_of_ascii(ty->name);
	}
}
