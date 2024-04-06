module test75f;

import config;
import cppconvhelpers;

struct X
{
	struct S {
		int i;
	}S* s;
}

void f(X.S* s)
{
	X x;
	x.s = s;
}

