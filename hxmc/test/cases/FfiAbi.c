// The C side of FfiAbi.hx, built per target by the corpus harness (zig cc):
// structs by value of every class of each ABI's rules.
#include <stdint.h>
typedef struct { float x, y; } F2;                                // 8: SSE; Win64 a register; HFA
typedef struct { double a, b, c, d; } D4;                         // 32: MEMORY; Win64 a copy; HFA
typedef struct { int32_t i; float f; } IF;                        // 8: INTEGER (mixed)
typedef struct { uint8_t a, b, c; } C3;                           // 3: Win64 a copy
typedef struct { double d; int64_t l; } DL;                       // 16: SSE, INTEGER
typedef struct { int64_t l; double d; } LD;                       // 16: INTEGER, SSE
typedef struct { int32_t a, b, c; } I3;                           // 12
typedef struct { float x, y, z; } F3;                             // 12: SSE, SSE; HFA
typedef struct { double d; float f; } DF;                         // 16: SSE, SSE
typedef struct { int16_t s; double d; } SD;                       // 16: INTEGER, SSE
typedef struct { int64_t a, b, c; } L3;                           // 24: MEMORY
typedef struct { double a; int64_t b; int32_t c; double d; uint16_t e; } B40; // 40
typedef struct { int16_t a, b, c; } S6;                           // 6: Win64 a copy

F2 a_f2(float x, float y) { F2 r = {x, y}; return r; }
double a_f2_sum(F2 v) { return v.x + 10 * v.y; }
F2 a_f2_twice(F2 v) { F2 r = {2 * v.x, 2 * v.y}; return r; }
D4 a_d4(double a, double b, double c, double d) { D4 r = {a, b, c, d}; return r; }
double a_d4_sum(D4 v) { return v.a + 10 * v.b + 100 * v.c + 1000 * v.d; }
D4 a_d4_twice(D4 v) { D4 r = {2 * v.a, 2 * v.b, 2 * v.c, 2 * v.d}; return r; }
IF a_if(int32_t i, float f) { IF r = {i, f}; return r; }
double a_if_sum(IF v) { return v.i + 10 * v.f; }
IF a_if_twice(IF v) { IF r = {2 * v.i, 2 * v.f}; return r; }
C3 a_c3(int32_t a, int32_t b, int32_t c) { C3 r = {a, b, c}; return r; }
int32_t a_c3_sum(C3 v) { return v.a + 1000 * v.b + 1000000 * v.c; }
C3 a_c3_twice(C3 v) { C3 r = {2 * v.a, 2 * v.b, 2 * v.c}; return r; }
DL a_dl(double d, int64_t l) { DL r = {d, l}; return r; }
double a_dl_sum(DL v) { return v.d + 10 * v.l; }
DL a_dl_twice(DL v) { DL r = {2 * v.d, 2 * v.l}; return r; }
LD a_ld(int64_t l, double d) { LD r = {l, d}; return r; }
double a_ld_sum(LD v) { return v.l + 10 * v.d; }
LD a_ld_twice(LD v) { LD r = {2 * v.l, 2 * v.d}; return r; }
I3 a_i3(int32_t a, int32_t b, int32_t c) { I3 r = {a, b, c}; return r; }
int64_t a_i3_sum(I3 v) { return v.a + 1000LL * v.b + 1000000LL * v.c; }
I3 a_i3_twice(I3 v) { I3 r = {2 * v.a, 2 * v.b, 2 * v.c}; return r; }
F3 a_f3(float x, float y, float z) { F3 r = {x, y, z}; return r; }
double a_f3_sum(F3 v) { return v.x + 10 * v.y + 100 * v.z; }
F3 a_f3_twice(F3 v) { F3 r = {2 * v.x, 2 * v.y, 2 * v.z}; return r; }
DF a_df(double d, float f) { DF r = {d, f}; return r; }
double a_df_sum(DF v) { return v.d + 10 * v.f; }
DF a_df_twice(DF v) { DF r = {2 * v.d, 2 * v.f}; return r; }
SD a_sd(int32_t s, double d) { SD r = {s, d}; return r; }
double a_sd_sum(SD v) { return v.s + 10 * v.d; }
SD a_sd_twice(SD v) { SD r = {2 * v.s, 2 * v.d}; return r; }
L3 a_l3(int64_t a, int64_t b, int64_t c) { L3 r = {a, b, c}; return r; }
int64_t a_l3_sum(L3 v) { return v.a + 1000 * v.b + 1000000 * v.c; }
L3 a_l3_twice(L3 v) { L3 r = {2 * v.a, 2 * v.b, 2 * v.c}; return r; }
B40 a_b40(double a, int64_t b, int32_t c, double d, int32_t e) { B40 r = {a, b, c, d, e}; return r; }
double a_b40_sum(B40 v) { return v.a + 10 * v.b + 100 * v.c + 1000 * v.d + 10000 * v.e; }
B40 a_b40_twice(B40 v) { B40 r = {2 * v.a, 2 * v.b, 2 * v.c, 2 * v.d, 2 * v.e}; return r; }
S6 a_s6(int32_t a, int32_t b, int32_t c) { S6 r = {a, b, c}; return r; }
int32_t a_s6_sum(S6 v) { return v.a + 100 * v.b + 10000 * v.c; }
S6 a_s6_twice(S6 v) { S6 r = {2 * v.a, 2 * v.b, 2 * v.c}; return r; }

// the integer registers run out: LD still fits, DL and what follows go on the stack
double a_gprs(int32_t a, int32_t b, int32_t c, int32_t d, int32_t e, LD x, double f, DL y, int32_t g) {
	return a + 2 * b + 3 * c + 4 * d + 5 * e + 10 * x.l + 100 * x.d + 1000 * f + 10000 * y.d + 100000 * y.l + 1000000 * g;
}
// the float registers run out: F2 and DF on the stack, then a double
double a_xmms(double d0, double d1, double d2, double d3, double d4, double d5, double d6, double d7, F2 v, DF w, double z, int32_t k) {
	return d0 + d1 + d2 + d3 + d4 + d5 + d6 + d7 + 10 * v.x + 100 * v.y + 1000 * w.d + 10000 * w.f + 100000 * z + 1000000 * k;
}
// structs in memory and small ones together
double a_mixed(D4 a, B40 b, C3 c, int32_t k, F3 f, L3 l, S6 s) {
	return a_d4_sum(a) + a_b40_sum(b) + a_c3_sum(c) + k + a_f3_sum(f) + a_l3_sum(l) + a_s6_sum(s);
}
// a result through memory with every integer register taken by arguments
B40 a_sret(int32_t a, int32_t b, int32_t c, int32_t d, int32_t e, int32_t f, double x, B40 in) {
	B40 r = {in.a + a, in.b + b, in.c + c, in.d + x, (uint16_t)(in.e + d + e + f)};
	return r;
}
// a function pointer (@:hxmc.indirect)
void *a_fnptr(void) { return (void *)a_dl_twice; }
// called in a safe region (not @:hxmc.fast)
DL a_dl_slow(DL v) { return a_dl_twice(v); }
B40 a_b40_slow(B40 v) { return a_b40_twice(v); }

// callbacks (@:hxmc.callback) taking and returning structs by value
double a_cb_f2(F2 (*f)(F2, double)) { F2 v = {1.5f, -2}; F2 r = f(v, 3); return r.x + 10 * r.y; }
double a_cb_d4(D4 (*f)(D4)) { D4 v = {1, 2, 3, 4}; D4 r = f(v); return a_d4_sum(r); }
double a_cb_if(IF (*f)(int32_t, IF)) { IF v = {-7, 0.25f}; IF r = f(5, v); return r.i + 10 * r.f; }
int32_t a_cb_c3(C3 (*f)(C3)) { C3 v = {1, 2, 3}; C3 r = f(v); return a_c3_sum(r); }
double a_cb_dl(DL (*f)(DL, LD)) { DL v = {0.5, 9}; LD w = {4, 0.25}; DL r = f(v, w); return r.d + 10 * r.l; }
double a_cb_f3(F3 (*f)(F3, F3)) { F3 a = {1, 2, 3}, b = {0.5f, 0.25f, 0.125f}; F3 r = f(a, b); return a_f3_sum(r); }
double a_cb_df(DF (*f)(DF)) { DF v = {1.25, 2.5f}; DF r = f(v); return r.d + 10 * r.f; }
double a_cb_b40(B40 (*f)(B40, double)) { B40 v = {0.5, 3, -4, 1.5, 7}; B40 r = f(v, 2); return a_b40_sum(r); }
int32_t a_cb_s6(S6 (*f)(S6)) { S6 v = {1, -2, 3}; S6 r = f(v); return a_s6_sum(r); }
int64_t a_cb_l3(L3 (*f)(L3, L3)) { L3 a = {1, 2, 3}, b = {10, 20, 30}; L3 r = f(a, b); return a_l3_sum(r); }
// the registers run out before the structs
double a_cb_spill(double (*f)(int32_t, int32_t, int32_t, int32_t, int32_t, LD, double, double, double, double, double, double, double, DF, F2, DL, I3)) {
	LD x = {2, 3};
	DF w = {4, 5};
	F2 v = {6, 7};
	DL y = {8, 9};
	I3 z = {10, 11, 12};
	return f(1, 2, 3, 4, 5, x, 1, 1, 1, 1, 1, 1, 1, w, v, y, z);
}
