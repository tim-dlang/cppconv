
module test368;

import config;
import cppconvhelpers;

int g(T)(int i)
{
    return i;
}

int h(T, T2)(int i)
{
    return i;
}

extern(C++, class) struct C(T)
{
}

extern(C++, class) struct C2(T, T2)
{
private:
    int f(int i)
    {
        return i;
    }
}

int f(T)()
{
    /+ int[0]  +/ auto arr = mixin(buildStaticArray!(q{int}, q{
        1,
        g!(C!(T)) (2),
        3,
        g!(T)(4),
        g!(T)(5),
        C2!(T, T).f(6),
        9}))
    ;
    return arr. ptr[1];
}

