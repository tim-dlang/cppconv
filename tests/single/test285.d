module test285;

import config;
import cppconvhelpers;

struct Size
{
}

extern(C++, class) struct C
{
public:
	void resize(int w, int h);
	void resize(ref const(Size) size);
}

void f()
{
	C c;
	c.resize(100, 200);
}

