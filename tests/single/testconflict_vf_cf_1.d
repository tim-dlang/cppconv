module testconflict_vf_cf_1;

import config;
import cppconvhelpers;

__gshared const(int) y = 1;

struct A
{
    static void X(int);
}

struct B
{
    alias X = int;
}

struct C1(T)
{
    static void f()
    {
        T.X(y);
    }
}

void g1()
{
    C1!(A).f();
    // C1<B>::f(); // error: missing 'typename' prior to dependent type name 'B::X'
}

/*
template <typename T>
struct C2
{
    static void f()
    {
        typename T::X(y);
    }
};

void g2()
{
    // C2<A>::f(); // error: typename specifier refers to non-type member 'X' in 'A'
    C2<B>::f();
}
*/

