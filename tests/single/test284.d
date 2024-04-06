module test284;

import config;
import cppconvhelpers;

void g();
void h();
void f(int x)
{
/+ #ifdef DEF +/
	static if (defined!"DEF")
	{
    	if (x)
    		g();
    	else
    /+ #endif +/
    		h();
	}
	else
	{
    h();
	}
}

