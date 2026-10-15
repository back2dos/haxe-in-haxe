// C library functions for hxmc's static Linux runtime (hxmc/c/mkrt.sh)
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

#ifdef __x86_64__
// memset: musl's handles small sizes with byte loops and branches; here
// sizes up to 64 take overlapping word stores (few branches), up to 256 a
// loop of 32 bytes, larger ones rep stosq to an aligned destination (the
// unaligned first and last words stored apart). musl's memcpy stays:
// replacing it measured slower on alloc.
typedef uint32_t __attribute__((may_alias, aligned(1))) u32u;
typedef uint16_t __attribute__((may_alias, aligned(1))) u16u;

void *memset(void *dst, int c, size_t n) {
	unsigned char *d = dst;
	uint64_t v = (uint64_t)(unsigned char)c * 0x0101010101010101ull;
	if (n <= 16) {
		if (n >= 8) {
			*(u64u *)d = v;
			*(u64u *)(d + n - 8) = v;
		} else if (n >= 4) {
			*(u32u *)d = (uint32_t)v;
			*(u32u *)(d + n - 4) = (uint32_t)v;
		} else if (n >= 2) {
			*(u16u *)d = (uint16_t)v;
			*(u16u *)(d + n - 2) = (uint16_t)v;
		} else if (n == 1)
			*d = (unsigned char)c;
		return dst;
	}
	if (n <= 64) {
		*(u64u *)d = v;
		*(u64u *)(d + 8) = v;
		*(u64u *)(d + n - 16) = v;
		*(u64u *)(d + n - 8) = v;
		if (n > 32) {
			*(u64u *)(d + 16) = v;
			*(u64u *)(d + 24) = v;
			*(u64u *)(d + n - 32) = v;
			*(u64u *)(d + n - 24) = v;
		}
		return dst;
	}
	if (n <= 256) {
		for (size_t k = 0; k + 32 <= n; k += 32) {
			*(u64u *)(d + k) = v;
			*(u64u *)(d + k + 8) = v;
			*(u64u *)(d + k + 16) = v;
			*(u64u *)(d + k + 24) = v;
		}
		*(u64u *)(d + n - 32) = v;
		*(u64u *)(d + n - 24) = v;
		*(u64u *)(d + n - 16) = v;
		*(u64u *)(d + n - 8) = v;
		return dst;
	}
	*(u64u *)d = v;
	*(u64u *)(d + n - 8) = v;
	size_t adj = 8 - ((uintptr_t)d & 7);
	d += adj;
	size_t q = (n - adj) >> 3;
	__asm__ volatile("rep stosq" : "+D"(d), "+c"(q) : "a"(v) : "memory");
	return dst;
}
#endif
