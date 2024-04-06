module test75e;

import config;
import cppconvhelpers;

struct S{}
struct X
{
	struct S__1{}
	/+
	struct S;
	+/S__1* s;
}

void f(
X.S__1*
 s)
{
	X x;
	x.s = s;
}

