// The C side of Ffi.hx, built per target by the corpus harness (zig cc).
#include <stdint.h>
#include <stdbool.h>
#include <stdarg.h>
#include <stddef.h>
typedef struct { int32_t x, y; double w; uint8_t tag; int16_t s; float f; void *next; } Rect;
int32_t t_add(int32_t a, int32_t b) { return a + b; }
int8_t t_neg8(int8_t a) { return (int8_t)-a; }
uint8_t t_inc_u8(uint8_t a) { return (uint8_t)(a + 1); }
int16_t t_mul16(int16_t a, int16_t b) { return (int16_t)(a * b); }
uint16_t t_add_u16(uint16_t a, uint16_t b) { return (uint16_t)(a + b); }
int64_t t_add64(int64_t a, int64_t b) { return a + b; }
float t_scale(float a, float b) { return a * b; }
double t_mix(int8_t a, float b, int64_t c, double d, uint8_t e, int16_t f, float g, double h, int32_t i, float j) {
	return a + b + c + d + e + f + g + h + i + j;
}
bool t_pos(int32_t v) { return v > 0; }
int32_t t_many(int32_t a, int32_t b, int32_t c, int32_t d, int32_t e, int32_t f, int32_t g, int32_t h, int32_t i, int32_t j, int32_t k, int32_t l) {
	return a + 2*b + 3*c + 4*d + 5*e + 6*f + 7*g + 8*h + 9*i + 10*j + 11*k + 12*l;
}
float t_many_f(float a, float b, float c, float d, float e, float f, float g, float h, float i, float j, float k) {
	return a + b + c + d + e + f + g + h + 2*i + 3*j + 4*k;
}
int32_t t_many_small(int8_t a, uint8_t b, int16_t c, uint16_t d, int8_t e, uint8_t f, int16_t g, uint16_t h, int8_t i, uint8_t j, int16_t k, uint16_t l) {
	return a + b + c + d + e + f + g + h + i + j + k + l;
}
int64_t t_sum(const int64_t *p, int32_t n) { int64_t s = 0; for (int i = 0; i < n; i++) s += p[i]; return s; }
void t_fill(Rect *r, int32_t x) { r->x = x; r->y = x * 2; r->w = x / 2.0; r->tag = 200; r->s = -5; r->f = 1.5f; r->next = r; }
double t_area(const Rect *r) { return r->x * r->y + r->w + r->tag + r->s + r->f; }
size_t t_strlen(const char *s) { size_t n = 0; while (s[n]) n++; return n; }
static const char greeting[] = "h\xc3\xa9llo";
const char *t_greet(void) { return greeting; }
int32_t t_sum_va(int32_t n, ...) { va_list ap; va_start(ap, n); int32_t s = 0; for (int i = 0; i < n; i++) s += va_arg(ap, int32_t); va_end(ap); return s; }
double t_sum_vad(int32_t n, ...) { va_list ap; va_start(ap, n); double s = 0; for (int i = 0; i < n; i++) s += va_arg(ap, double); va_end(ap); return s; }
int32_t t_sizeof_rect(void) { return (int32_t)sizeof(Rect); }
int32_t t_offset_next(void) { return (int32_t)offsetof(Rect, next); }
int32_t t_sub(int32_t a, int32_t b) { return a - b; }
// callbacks: C calls Haxe through a function pointer
typedef int32_t (*cb_i)(int32_t);
int32_t t_apply(cb_i f, int32_t v) { return f(v) + 1; }
typedef double (*cb_d)(void *, double);
double t_apply_d(cb_d f, void *ctx, double v) { return f(ctx, v) * 2; }
// a C function's address, for a call through a pointer (@:hxmc.indirect)
void *t_fnptr(void) { return (void *)t_add; }
int32_t t_apply_fast(cb_i f, int32_t v) { return f(v) + 1; }
