module test328;

import config;
import cppconvhelpers;

struct List(T)
{
	T* data();
}

struct S
{
}

void g(S* s);

void f(ref List!(S) l)
{
	g(l.data());
}

