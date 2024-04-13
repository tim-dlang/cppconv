module test128;

import config;
import cppconvhelpers;

class P
{
public:
	/+ virtual +/ void f();
}
class C: P
{
public:
	final override void f();
}
void f()
{
    import core.stdcpp.new_;

	int final_;
	C c = cpp_new!C;
	c.f();
}

