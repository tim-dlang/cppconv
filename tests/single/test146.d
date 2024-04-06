module test146;

import config;
import cppconvhelpers;

enum generated_test146_0{A=2,B,C}
struct S
{
	generated_test146_0 x;
}
// self alias: alias S = S;

void f(S* s)
{
	s.x = generated_test146_0.A;
}

int g(S* s)
{
	switch(s.x)
	{
		case generated_test146_0.A:
		return 42;
		case generated_test146_0.B:
		return 43;
		case generated_test146_0.C:
		return 44;default:

	}
	return -1;
}

