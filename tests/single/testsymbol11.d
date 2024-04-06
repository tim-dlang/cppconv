module testsymbol11;

import config;
import cppconvhelpers;

extern(C++, class) struct C(T, S)
{
public:
	void f(ref T x, ref S y)
	{
		x.i = y.i;
	}
}

