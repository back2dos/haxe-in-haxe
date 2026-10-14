// Runtime helpers of hxmc's generated code, linked into the runtime objects
// (hxmc/tools/mkrt.sh; bin/hxmc/rt-dev for hybrid builds): the slow paths
// that C writes inline, called from one instruction sequence each so that
// every allocation or reference store site has a short slow path.
#include "rt.h"

// rt_alloc_slow with the header assembled here (the type index is a
// link-time constant: it cannot be shifted into place by the linker)
void *hxmc_alloc_slow(uint32_t lo, uint32_t tindex, uint32_t bytes) {
	return rt_alloc_slow(((uint64_t)tindex << 32) | lo, bytes);
}

// the rest of rt_set_ptr's barrier once obj is known not to be young
void hxmc_barrier_slow(void *obj, void **slot, void *val, void *prev) {
	if ((char *)val >= rt_young_start && (char *)val < rt_young_end)
		if ((char *)prev < rt_young_start || (char *)prev >= rt_young_end) rt_write_barrier(obj, slot, val);
}

#ifdef __APPLE__
// the address of this thread's copy of the image's thread-local template:
// hxmc's code reaches the runtime's thread-local variables at their offsets
// from it (LinkMachO defines hxmc_tls_start, a descriptor of offset 0)
extern __thread char hxmc_tls_start;
void *hxmc_tls_base(void) { return &hxmc_tls_start; }
#endif
