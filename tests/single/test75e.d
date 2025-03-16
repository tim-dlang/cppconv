module test75e;

import config;
import cppconvhelpers;

struct S{}
struct X
{
	struct S{}
	/+
	struct S;
	+/S* s;
}

void f(
X.S*
 s)
{
	X x;
	x.s = s;
}

