module test322;

import config;
import cppconvhelpers;

extern(C++, class) struct C(T)
{
public:
	C!(T) createC1()
	{
		C!(T) r;
		return r;
	}

	struct S
	{
	}
	S createS1()
	{
		C!(T).S r;
		return r;
	}
}

