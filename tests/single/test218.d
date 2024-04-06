module test218;

import config;
import cppconvhelpers;


struct QArrayData
{
    int size;
    /+ unsigned int alloc : 31; +/
    uint bitfieldData_alloc;
    final uint alloc() const
    {
        return (bitfieldData_alloc >> 0) & 0x7fffffff;
    }
    final uint alloc(uint value)
    {
        bitfieldData_alloc = (bitfieldData_alloc & ~0x7fffffff) | ((value & 0x7fffffff) << 0);
        return value;
    }
    /+ unsigned int capacityReserved : 1; +/
    final uint capacityReserved() const
    {
        return (bitfieldData_alloc >> 31) & 0x1;
    }
    final uint capacityReserved(uint value)
    {
        bitfieldData_alloc = (bitfieldData_alloc & ~0x80000000) | ((value & 0x1) << 31);
        return value;
    }

    long offset; // in bytes from beginning of header

    void* data()
    {
        if(size == 0
                || offset < 0 || size_t(offset) >= QArrayData.sizeof)
		{}
        return reinterpret_cast!(char*)(&this) + offset;
    }
}

