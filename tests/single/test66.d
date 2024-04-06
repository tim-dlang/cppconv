module test66;

import config;
import cppconvhelpers;

struct S
{
	int id;
}

int f()
{
	S s;
	return s.id;
}
int g(S* s)
{
	return s.id;
}

