module testoverloading1;

import config;
import cppconvhelpers;

void f(int);
char* f(const(char)* );

void g()
{
	static if (defined!"DEF")
	{
    	int x = 42;
	}
	else
	{
    	const(char)* x = "test";
	}

	f(x);
}

