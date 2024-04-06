module test62f;

import config;
import cppconvhelpers;

enum E
{
	A,
	B,
	C
}
// self alias: alias E = E;

E g()
{
	return E.A;
}

