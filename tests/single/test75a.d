module test75a;

import config;
import cppconvhelpers;

struct X
{
	struct S;
	S* s;
}

void f(X.S* s)
{
	X x;
	x.s = s;
}

