#define CHAR_BIT 8
#define bitsizeof(x) (CHAR_BIT * sizeof(x))
#define MSB(x, bits) ((x) & (~0ULL << (bitsizeof(x) - (bits))))
typedef unsigned long long uintmax_t;

void f(unsigned char c)
{
	uintmax_t val = c & 127;
	if (!val || MSB(val, 7)) {
	}
}
