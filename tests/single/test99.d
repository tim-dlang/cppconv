module test99;

import config;
import cppconvhelpers;

void v(const(char)* t, ...);
void f()
{
	char[20] buf;
	v("%s", buf.ptr);
}

