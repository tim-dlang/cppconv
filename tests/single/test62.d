module test62;

import config;
import cppconvhelpers;

enum E
{
	A,
	B,
	C
}

void f(E);

void g()
{
	f(E.A);
}

