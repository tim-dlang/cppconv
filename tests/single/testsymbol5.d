module testsymbol5;

import config;
import cppconvhelpers;

extern(C++, "n")
{
	struct S
	{
	}
}

extern(C++, "n")
{
	void f(S* s);
}

void g()
{
	/+ n:: +/S s;
	/+ n:: +/f(&s);
}

