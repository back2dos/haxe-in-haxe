// C library functions for hxmc's static Linux runtime (hxmc/tools/mkrt.sh)
// where musl's compare one byte at a time and the runtime leans on them
// (haxe.io.Bytes.compare, string comparison): 8 bytes at a time here.
// Built freestanding (no builtins), so the loops stay loops.
#include <stddef.h>
#include <stdint.h>

typedef uint64_t __attribute__((may_alias, aligned(1))) u64u;

int memcmp(const void *a, const void *b, size_t n) {
	const unsigned char *p = a, *q = b;
	while (n >= 8) {
		uint64_t x = *(const u64u *)p, y = *(const u64u *)q;
		if (x != y) {
			// the first differing byte decides: compare in big-endian order
			x = __builtin_bswap64(x);
			y = __builtin_bswap64(y);
			return x < y ? -1 : 1;
		}
		p += 8;
		q += 8;
		n -= 8;
	}
	for (; n > 0; n--, p++, q++)
		if (*p != *q) return *p - *q;
	return 0;
}

int bcmp(const void *a, const void *b, size_t n) {
	const unsigned char *p = a, *q = b;
	while (n >= 8) {
		if (*(const u64u *)p != *(const u64u *)q) return 1;
		p += 8;
		q += 8;
		n -= 8;
	}
	for (; n > 0; n--, p++, q++)
		if (*p != *q) return 1;
	return 0;
}
