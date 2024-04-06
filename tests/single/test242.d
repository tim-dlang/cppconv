module test242;

import config;
import cppconvhelpers;

struct S
{
}

void f(ref const(S) s);

ref S g()
{
    extern(D) static __gshared S s;
    f(s);
    return s;
}

void h()
{
    S s;
    s = g();
}

