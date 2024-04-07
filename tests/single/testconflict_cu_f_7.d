module testconflict_cu_f_7;

import config;
import cppconvhelpers;

/+ #define CHAR_BIT 8 +/
enum CHAR_BIT = 8;
/+ #define bitsizeof(x) (CHAR_BIT * sizeof(x)) +/
extern(D) alias bitsizeof = function string(string x)
{
    return mixin(interpolateMixin(q{(imported!q{testconflict_cu_f_7}.CHAR_BIT * ($(x)). sizeof)}));
};
/+ #define MSB(x, bits) ((x) & (~0ULL << (bitsizeof(x) - (bits)))) +/
extern(D) alias MSB = function string(string x, string bits)
{
    return mixin(interpolateMixin(q{(($(x)) & (~0UL << (mixin(imported!q{testconflict_cu_f_7}.bitsizeof(q{$(x)})) - ($(bits)))))}));
};
alias uintmax_t = ulong;

void f(ubyte  c)
{
	uintmax_t val = c & 127;
	if (!val || mixin(MSB(q{val}, q{7}))) {
	}
}

