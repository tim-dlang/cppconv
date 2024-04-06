module test258;

import config;
import cppconvhelpers;

extern(C++, class) struct Template(T)
{
public:
	static void f();
	struct S
	{
	}
}

void g()
{
	Template!(int).f();
	Template!(int).S x;
}

