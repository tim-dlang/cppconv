module test393;

import config;
import cppconvhelpers;

struct S
{
    /+ unsigned long long a : 64; +/
    ulong bitfieldData_a;
    ulong a() const nothrow
    {
        return (bitfieldData_a >> 0) & 0xffffffffffffffff;
    }
    ulong a(ulong value) nothrow
    {
        bitfieldData_a = (bitfieldData_a & ~0xffffffffffffffff) | ((value & 0xffffffffffffffff) << 0);
        return value;
    }
}

