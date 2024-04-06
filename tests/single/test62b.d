module test62b;

import config;
import cppconvhelpers;

enum E
{
	A,
	B,
	C
}
// self alias: alias E = E;

void f(E);

void g()
{
	f(E.A);
}

