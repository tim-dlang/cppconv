module test389;

import config;
import cppconvhelpers;

extern(C++, class) struct C
{
}
C* createC();
void f()
{
    if (C* x = createC())
    {}
}

