module test333;

import config;
import cppconvhelpers;

struct Base
{
    void f();
}
struct Child
{
    public Base base0;
    alias base0 this;
}

