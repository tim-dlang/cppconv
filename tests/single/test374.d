module test374;

import config;
import cppconvhelpers;

class C
{
private:
    /+ virtual +/~this();

    /+ int i1 : 2; +/
    ubyte bitfieldData_i1;
    final int i1() const
    {
        return (bitfieldData_i1 >> 0) & 0x3;
    }
    final int i1(int value)
    {
        bitfieldData_i1 = (bitfieldData_i1 & ~0x3) | ((value & 0x3) << 0);
        return value;
    }
    /+ int i2 : 6; +/
    final int i2() const
    {
        return (bitfieldData_i1 >> 2) & 0x3f;
    }
    final int i2(int value)
    {
        bitfieldData_i1 = (bitfieldData_i1 & ~0xfc) | ((value & 0x3f) << 2);
        return value;
    }
}

