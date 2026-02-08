module test379;

import config;
import cppconvhelpers;

class Base
{
public:
    /+ virtual +/~this()
    {}

    final void f(int i)
    {}
}

class Child : Base
{
public:
    alias f = Base.f;
    final void f(const(char)* s)
    {}
}

int main()
{
    import core.stdcpp.new_;

    Child c = cpp_new!Child();
    c.f(1);
    c.f("".ptr);
    return 0;
}

