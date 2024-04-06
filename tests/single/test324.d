module test324;

import config;
import cppconvhelpers;

extern(C++, class) struct C(T)
{

}

void f(T)()
{
	C!(T) x;
}

