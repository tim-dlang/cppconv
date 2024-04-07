module test256;

import config;
import cppconvhelpers;

enum E
{
	A,
	B
}

struct S
{

}

void* f(int);

void g()
{
	S* s = cast(S*) (f(E.A));
}


