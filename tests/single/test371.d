module test371;

import config;
import cppconvhelpers;

extern(C++, class) struct C(T)
{
}

void f()
{
    import core.stdcpp.new_;

    C!(int)* c = cpp_new!(C!(int))();

    int* p = cpp_new!int();
}

