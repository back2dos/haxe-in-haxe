// The C side of FfiStruct.hx, built per target by the corpus harness (zig cc).
#include <stdint.h>
typedef struct { double r, g, b, a; } Color;
typedef struct { double x, y; } Pt;
typedef struct { Pt origin; Pt size; } Box;
typedef struct { float x, y, z; } F3;
typedef struct { double d; } One;
typedef struct { uint64_t w, h, d; } Size3;
typedef struct { double x, y, w, h, zn, zf; } View;
typedef struct { int32_t a; int8_t b; } Small;
typedef struct { int64_t a; int32_t b; } Mid;
typedef struct { uint8_t a, b, c; } Tiny;
typedef struct { int32_t a; float f; } Mixed;

double s_color_sum(Color c) { return c.r + 2 * c.g + 3 * c.b + 4 * c.a; }
Color s_color(double r, double g, double b, double a) { Color c = {r, g, b, a}; return c; }
Box s_box(double x, double y, double w, double h) { Box b = {{x, y}, {w, h}}; return b; }
Box s_box_slow(double x, double y, double w, double h) { Box b = {{x, y}, {w, h}}; return b; }
Size3 s_size3_slow(uint64_t w, uint64_t h, uint64_t d) { Size3 s = {w, h, d}; return s; }
double s_box_area(void *self, void *sel, Box b) { return (b.size.x - b.origin.x) * (b.size.y - b.origin.y) + (self == sel); }
F3 s_f3_scale(F3 v, float k) { F3 r = {v.x * k, v.y * k, v.z * k}; return r; }
One s_one(One o) { One r = {o.d * 3}; return r; }
Size3 s_size3(uint64_t w, uint64_t h, uint64_t d) { Size3 s = {w, h, d}; return s; }
uint64_t s_size3_vol(Size3 s, int32_t k) { return s.w * s.h * s.d + k; }
View s_view(View v) { View r = {v.zf, v.zn, v.h, v.w, v.y, v.x}; return r; }
Small s_small(Small s) { Small r = {s.a * 2, (int8_t)(s.b - 1)}; return r; }
Mid s_mid(Mid m, int32_t k) { Mid r = {m.a + k, m.b - k}; return r; }
Tiny s_tiny(Tiny t) { Tiny r = {t.c, t.b, t.a}; return r; }
Mixed s_mixed(Mixed m) { Mixed r = {m.a + 1, m.f * 2}; return r; }
// the register files exhausted: the struct and what follows on the stack
int64_t s_spill_int(int32_t a, int32_t b, int32_t c, int32_t d, int32_t e, int32_t f, int32_t g, Mid m, int32_t z) {
	return a + b + c + d + e + f + g + 1000 * m.a + 100 * m.b + z;
}
double s_spill_hfa(double a, double b, double c, double d, double e, double f, double g, Color k, double z) {
	return a + b + c + d + e + f + g + 1000 * k.r + 100 * k.g + 10 * k.b + k.a + z / 8;
}
float s_spill_f3(float a, float b, float c, float d, float e, float f, float g, float h, F3 v, float z, F3 w) {
	return a + b + c + d + e + f + g + h + 100 * v.x + 10 * v.y + v.z + z / 4 + w.x * w.y * w.z;
}
void *s_fnptr(void) { return (void *)s_box_area; }
