// Runtime helpers of hxmc's generated code, linked into the runtime objects
// (hxmc/c/mkrt.sh): the slow paths of allocation and reference stores,
// called from one instruction sequence each so that every allocation or
// reference store site has a short slow path.
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

#ifdef _WIN32
// Windows: a crash names its exception and the address in the image (the
// image has no unwind information for generated code, so neither a
// debugger's stack trace nor an unhandled-exception filter can be relied
// on). Installed by a TLS callback, before the C runtime starts; written
// without the C library.
#include <windows.h>
static void hxmc_hex(char *p, unsigned long long v, int n) {
	for (int i = n - 1; i >= 0; i--, v >>= 4) p[i] = "0123456789abcdef"[v & 15];
}
static LONG CALLBACK hxmc_crash(EXCEPTION_POINTERS *e) {
	DWORD c = e->ExceptionRecord->ExceptionCode;
	if (c == EXCEPTION_ACCESS_VIOLATION || c == EXCEPTION_ILLEGAL_INSTRUCTION || c == EXCEPTION_PRIV_INSTRUCTION || c == EXCEPTION_STACK_OVERFLOW ||
		c == EXCEPTION_INT_DIVIDE_BY_ZERO || c == EXCEPTION_DATATYPE_MISALIGNMENT || c == EXCEPTION_IN_PAGE_ERROR || c == 0xC00000AA) {
		char *a = (char *)e->ExceptionRecord->ExceptionAddress, *base = (char *)GetModuleHandleA(NULL);
		char msg[] = "hxmc: exception 0x00000000 at image + 0x0000000000000000\n";
		hxmc_hex(msg + 18, c, 8);
		hxmc_hex(msg + 40, (unsigned long long)(a - base), 16);
		DWORD n;
		WriteFile(GetStdHandle(STD_ERROR_HANDLE), msg, sizeof msg - 1, &n, NULL);
	}
	return EXCEPTION_CONTINUE_SEARCH;
}
static void NTAPI hxmc_crash_init(PVOID h, DWORD reason, PVOID r) {
	(void)h;
	(void)r;
	if (reason != DLL_PROCESS_ATTACH) return;
	AddVectoredExceptionHandler(0, hxmc_crash);
	char v[4];
	if (GetEnvironmentVariableA("HXMC_TRACE", v, sizeof v) > 0) {
		DWORD n;
		WriteFile(GetStdHandle(STD_ERROR_HANDLE), "hxmc: started\n", 14, &n, NULL);
	}
}
__attribute__((section(".CRT$XLB"), used)) PIMAGE_TLS_CALLBACK hxmc_crash_tls = hxmc_crash_init;
#endif
