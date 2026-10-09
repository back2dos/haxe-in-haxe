// EXPERIMENTAL runtime for the C output of backend/ (see bench/WASM-BACKEND.md).
// Precise generational copying GC in the style of OCaml's: objects are
// bump-allocated in a nursery; survivors are copied to an old space, which
// is itself collected by copying. Roots are an explicit shadow stack (every
// reference-typed local lives in a frame slot `fr[k]`), the global table and
// a remembered set filled by the write barrier.
#pragma once
#include <stdint.h>
#include <string.h>

#ifdef __cplusplus
extern "C" {
#endif

// Object layout: pointer to the payload; the header word precedes it.
// Payload = 8-byte slots. Header: [0..31] slot count, [32..47] type index,
// [48..55] kind.
enum { K_OBJ = 0, K_PARR = 1, K_RAW = 2, K_FWD = 0xFF };
#define HDR(p) (((uint64_t *)(p))[-1])
#define NSLOTS(p) ((uint32_t)HDR(p))
#define KIND(p) ((uint32_t)((HDR(p) >> 48) & 0xFF))
#define TINDEX(p) ((uint32_t)((HDR(p) >> 32) & 0xFFFF))

#define FI(p, i) (((int32_t *)(p))[2 * (i)])
#define FD(p, i) (((double *)(p))[i])
#define FP(p, i) (((void **)(p))[i])

extern char *rt_young_ptr, *rt_young_limit;
extern void **rt_sp;           // shadow stack top
extern void **rt_globals;      // global roots
extern const uint64_t *rt_type_ptrmaps; // per type index: bitmap of pointer slots

void *rt_alloc_slow(uint64_t header, uint32_t bytes);
void rt_write_barrier(void *obj, void **slot, void *val);
void rt_init(int nglobals);

static inline void *rt_alloc(uint32_t nslots, uint32_t tindex, uint32_t kind) {
	uint32_t bytes = 8 * (nslots + 1);
	uint64_t h = (uint64_t)nslots | ((uint64_t)tindex << 32) | ((uint64_t)kind << 48);
	char *p = rt_young_ptr;
	if (__builtin_expect(rt_young_limit - p >= (intptr_t)bytes, 1)) {
		rt_young_ptr = p + bytes;
		*(uint64_t *)p = h;
		void *o = p + 8;
		memset(o, 0, bytes - 8);
		return o;
	}
	return rt_alloc_slow(h, bytes);
}

// For objects whose every slot is written before the next GC point.
static inline void *rt_alloc_init(uint32_t nslots, uint32_t tindex, uint32_t kind) {
	uint32_t bytes = 8 * (nslots + 1);
	uint64_t h = (uint64_t)nslots | ((uint64_t)tindex << 32) | ((uint64_t)kind << 48);
	char *p = rt_young_ptr;
	if (__builtin_expect(rt_young_limit - p >= (intptr_t)bytes, 1)) {
		rt_young_ptr = p + bytes;
		*(uint64_t *)p = h;
		return p + 8;
	}
	return rt_alloc_slow(h, bytes);
}

extern char *rt_young_start;
// Store a reference into a heap object: remember old-to-young pointers.
static inline void rt_set_ptr(void *obj, void **slot, void *val) {
	*slot = val;
	if ((char *)obj < rt_young_start || (char *)obj >= rt_young_limit)
		if ((char *)val >= rt_young_start && (char *)val < rt_young_limit) rt_write_barrier(obj, slot, val);
}

// Exceptions: __builtin_setjmp handlers chained through the C stack.
#if defined(__EMSCRIPTEN__) || defined(__TINYC__) // no __builtin_setjmp
#include <setjmp.h>
#define RT_SETJMP(b) setjmp(b)
#define RT_LONGJMP(b) longjmp(b, 1)
typedef jmp_buf rt_jmpbuf;
#else
#define RT_SETJMP(b) __builtin_setjmp(b)
#define RT_LONGJMP(b) __builtin_longjmp(b, 1)
typedef void *rt_jmpbuf[5];
#endif
typedef struct rt_handler {
	rt_jmpbuf buf;
	struct rt_handler *prev;
	void **sp;
} rt_handler;
extern rt_handler *rt_hcur;
extern void *rt_exn;

// try/catch. Natively: setjmp handlers (cheap). Under Emscripten the
// generated code is compiled as C++ so that try maps to wasm exception
// handling: wasm setjmp makes LLVM store every local around every call
// (26x code growth, bench/WASM-BACKEND.md section 4).
#if defined(__cplusplus) && defined(__EMSCRIPTEN__)
}
struct rt_cxx_exn {};
#define RT_TRY(h) { void **h##_sp = rt_sp; try {
#define RT_CATCH(h) } catch (rt_cxx_exn &) { rt_sp = h##_sp;
#define RT_END_TRY(h) } }
#define RT_POP(h)
[[noreturn]] static inline void rt_throw(void *v) {
	rt_exn = v;
	throw rt_cxx_exn();
}
extern "C" {
#else
#define RT_TRY(h) { rt_handler h; h.prev = rt_hcur; h.sp = rt_sp; rt_hcur = &h; if (RT_SETJMP(h.buf) == 0) {
#define RT_CATCH(h) rt_hcur = h.prev; } else { rt_hcur = h.prev; rt_sp = h.sp;
#define RT_END_TRY(h) } }
#define RT_POP(h) rt_hcur = h.prev;
__attribute__((noreturn)) void rt_throw(void *v);
#endif

// Haxe Int semantics: wrapping 32-bit arithmetic.
#define IADD(a, b) ((int32_t)((uint32_t)(a) + (uint32_t)(b)))
#define ISUB(a, b) ((int32_t)((uint32_t)(a) - (uint32_t)(b)))
#define IMUL(a, b) ((int32_t)((uint32_t)(a) * (uint32_t)(b)))
#define INEG(a) ((int32_t)(0u - (uint32_t)(a)))
#define ISHL(a, b) ((int32_t)((uint32_t)(a) << ((b) & 31)))
#define ISHR(a, b) ((int32_t)(a) >> ((b) & 31))
#define IUSHR(a, b) ((int32_t)((uint32_t)(a) >> ((b) & 31)))
static inline int32_t IMOD(int32_t a, int32_t b) { return b == 0 ? 0 : (b == -1 ? 0 : a % b); }

// Haxe Array<T>: object {len, data}; data is a K_RAW (scalars) or K_PARR array.
#define ARR_LEN(a) FI(a, 0)
#define ARR_DATA(a) FP(a, 1)
void *rt_arr_new(int raw, int32_t cap, uint32_t tindex);
void rt_arr_grow(void **arr_slot, int raw);

#ifdef __cplusplus
}
#endif
