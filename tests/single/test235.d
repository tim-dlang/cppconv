module test235;

import config;
import cppconvhelpers;

extern(C++, class) struct A
{
	public:
	alias Int = int;
}

extern(C++, class) struct B
{
public:
	A.Int i;
}

