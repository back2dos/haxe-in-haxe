// The hxmc runtime: what remains in C of strings (the rest is Haxe,
// hxmc/std/hxmc/rt/Str.hx and Dyn.hx): the shortest round-trip formatting
// of doubles, through the C library's printf and strtod.
#include "rt.h"
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

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
