module testconflict_cf_f_3;

import config;
import cppconvhelpers;

struct id{
	this(int){}
} // => cast
static if (!defined!"DEF")
{
void id__1(int); // => func call
}

__gshared int x;

void f()
{
	(mixin((!defined!"DEF") ? q{
        	/*(*/id__1/*)*/(x)
    	} : q{
        cast(id)(x)
    	}));
}

