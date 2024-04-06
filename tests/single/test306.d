module test306;

import config;
import cppconvhelpers;

void f();

extern(C++, class) struct C
{
private:
	void f();
	void g()
	{
		.f();
	}
}

