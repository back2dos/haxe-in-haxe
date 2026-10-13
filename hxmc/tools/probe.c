// The runtime's struct layouts and jmp_buf size on a target, which hxmc's
// code generators and data writer hard-code (hxmc/src/hxmc/Abi.hx):
//   zig cc -target <triple> -I hxc/rt -S -o - hxmc/tools/probe.c | grep -A1 probe_
// (each value is the initializer of a probe_<name> constant)
#include "rt.h"
#include <stddef.h>
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
