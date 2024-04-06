module test228;

import config;
import cppconvhelpers;

extern(C++, class) struct A
{
}

extern(C++, class) struct B
{
public:
    /+auto opCast(T : A)() const;+/
}

