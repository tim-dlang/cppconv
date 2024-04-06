module test231;

import config;
import cppconvhelpers;

extern(C++, class) struct A
{
public:
	void f();
}

extern(C++, class) struct B
{
    public A base0;
    alias base0 this;
public:
	/+ using A::f; +/
}

