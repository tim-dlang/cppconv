module test75b;

import config;
import cppconvhelpers;

struct S;
struct X
{
	S* s;
	S* s2;
}

void f(S* s)
{
	X x;
	x.s = s;
	x.s2 = s;
}

