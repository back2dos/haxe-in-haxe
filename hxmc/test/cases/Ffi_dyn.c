// The dynamic library of Ffi.hx (a DLL on Windows, a dylib on macOS; an
// object linked statically on Linux), built by the corpus harness (zig cc).
#include <stdint.h>
#ifdef _WIN32
#define EXPORT __declspec(dllexport)
#else
#define EXPORT __attribute__((visibility("default")))
#endif
EXPORT int32_t dyn_twice(int32_t v) { return 2 * v; }
EXPORT double dyn_hyp2(double a, double b) { return a * a + b * b; }
EXPORT const char *dyn_name(void) { return "ffidyn"; }
