module test376;

import config;
import cppconvhelpers;


extern(C++, class) struct QVLAStorage(size_t Size, size_t Align, size_t Prealloc)
{
private:
    /+ alignas(Align) +/ char[Prealloc * (Align > Size ? Align : Size)] array;

    static assert(( (array).length ) * char.sizeof);
}

