// The layouts hxmc's code generators and data writer hard-code
// (hxmc/src/hxmc/Abi.hx; the runtime's Haxe code reads the same tables:
// hxmc/std/hxmc/rt/Types.hx), written as C structures to check them per
// target, with the C library's jmp_buf (the handler of a try):
//   zig cc -target <triple> -S -o probe.s hxmc/deps/probe.c; grep -A1 probe_ probe.s
// (each value is the initializer of a probe_<name> constant). Development
// time only: not linked into anything.
#include <setjmp.h>
#include <stddef.h>
#include <stdint.h>
typedef struct { int32_t fid, slot; char kind; } rt_field;
typedef struct { int32_t fid; void *fn; int32_t sig; } rt_method;
typedef struct { int32_t fid; char kind; int32_t idx; void *ptr; } rt_static;
typedef struct {
	const char *name; uint8_t tk; int32_t super; uint32_t nslots; const uint64_t *ptrmap;
	uint32_t nfields; const rt_field *fields; uint32_t nmethods; const rt_method *methods;
	uint32_t nifaces; const int32_t *ifaces; int32_t tag; const int32_t *ctors;
	uint32_t nstatics; const rt_static *statics;
} rt_type;
typedef struct { uint32_t t; int32_t slot; char kind; void *fn; int32_t sig; } rt_icache;
typedef struct rt_handler { jmp_buf buf; struct rt_handler *prev; void **sp; } rt_handler;
#define P(name, v) const long probe_##name = (long)(v);
P(rt_type_size, sizeof(rt_type))
P(rt_type_tag, offsetof(rt_type, tag))
P(rt_type_super, offsetof(rt_type, super))
P(rt_type_nslots, offsetof(rt_type, nslots))
P(rt_type_fields, offsetof(rt_type, fields))
P(rt_type_methods, offsetof(rt_type, methods))
P(rt_type_statics, offsetof(rt_type, statics))
P(rt_field_size, sizeof(rt_field))
P(rt_method_size, sizeof(rt_method))
P(rt_method_fn, offsetof(rt_method, fn))
P(rt_method_sig, offsetof(rt_method, sig))
P(rt_static_size, sizeof(rt_static))
P(rt_static_idx, offsetof(rt_static, idx))
P(rt_static_ptr, offsetof(rt_static, ptr))
P(icache_size, sizeof(rt_icache))
P(icache_slot, offsetof(rt_icache, slot))
P(icache_kind, offsetof(rt_icache, kind))
P(icache_fn, offsetof(rt_icache, fn))
P(icache_sig, offsetof(rt_icache, sig))
P(handler_size, sizeof(rt_handler))
P(handler_prev, offsetof(rt_handler, prev))
P(handler_sp, offsetof(rt_handler, sp))
P(jmpbuf_align, _Alignof(rt_handler))
