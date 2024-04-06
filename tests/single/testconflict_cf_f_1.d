module testconflict_cf_f_1;

import config;
import cppconvhelpers;

static if (defined!"DEF")
{
alias id = int; // => cast
}
static if (!defined!"DEF")
{
void id(int); // => func call
}

__gshared int x;

auto f()
{
	return mixin((!defined!"DEF") ? q{
        	/*(*/id/*)*/(x)
    	} : q{
        cast(id)(x)
    	});
}

