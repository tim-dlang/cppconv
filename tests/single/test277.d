module test277;

import config;
import cppconvhelpers;

extern(C++, class) struct C
{
public:
	int f()
	{
		return E.X;
	}
	enum E
	{
		X
	}
}

