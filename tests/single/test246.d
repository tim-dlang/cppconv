module test246;

import config;
import cppconvhelpers;

extern(C++, class) struct C
{
public:
	@disable this();
	this(int x/+ = 4+/, int y = 5);
	void f(int x = 4, int y = 5);
}

