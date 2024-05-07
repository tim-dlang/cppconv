
module testconflict_tl_f_4;

import config;
import cppconvhelpers;

struct A
{
    int i;
}
struct B
{
    int i;
}

struct S
{
    int i1;

    int i2;
    int i3;
    static if (!defined!"DEF")
    {
        int i4;
        int i5;
    }

    A a;
    B b;
}

static if (defined!"DEF")
{
int f(T1, T2)(int i)
{
    return i;
}

alias a = int;
alias b = int;

}
static if (!defined!"DEF")
{

__gshared const(int) f = 1;
__gshared const(int) a = 2;
__gshared const(int) b = 3;

}

void g()
{
    S data = mixin("S(" ~ q{
                1
    }
    ~ (defined!"DEF" ? q{
        ,

                f!(a, b)(2)
    }:"")
    ~ (!defined!"DEF" ? q{
        ,f<a,b>(2)
    }:"")
    ~ (defined!"DEF" ? q{
        ,
                f!(a, b)(3)
    }:"")
    ~ (!defined!"DEF" ? q{
        ,f<a,b>(3)
    }:"")
    ~ q{
        ,

                A(4),
                B(5)
}
 ~ ")")    ;
}

