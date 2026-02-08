module test380;

import config;
import cppconvhelpers;

extern(C++, "n")
{
    struct S
    {
    }
    void g();
}

void f()
{
    alias S = /+ n:: +/.S;
    S* x;

    alias g = /+ n:: +/.g;
    g();
}

