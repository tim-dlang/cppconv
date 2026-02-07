
module test383;

import config;
import cppconvhelpers;

struct S
{
    this(const(char)* );
}

struct C
{
    static void f(ref const(S));
    static void f(const char *s) { auto tmp = S(s); f(tmp); }
}

void g()
{
    C.f("xyz");
    C.f(true ? "a" : "b");
}

