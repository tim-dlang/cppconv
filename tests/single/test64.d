module test64;

import config;
import cppconvhelpers;

__gshared int i;
__gshared double d;
void f()
{
	double y =
	/+ #ifdef DEF +/
	mixin((defined!"DEF") ? q{
        	i
    	} : q{
        	/+ #else +/
        	d
    	})	/+ #endif +/
		;
}

