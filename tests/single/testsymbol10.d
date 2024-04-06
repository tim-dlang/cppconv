module testsymbol10;

import config;
import cppconvhelpers;

extern(C++, class) struct C
{
public:
	// comment3a
	void f()
	{
		// comment3b
	}
	// comment5a
	int f(int x, int y)
	{
		// comment5b
		return x + y;
	}
	// comment1a
	void f(const(char)* s)
	{
		// comment1b
	}
	// comment4a
	void f(int/+[2]+/* arr)
	{
		// comment4b
	}
	// comment2a
	void f(double d)
	{
		// comment2b
	}
}

