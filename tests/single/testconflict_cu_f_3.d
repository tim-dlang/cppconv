module testconflict_cu_f_3;

import config;
import cppconvhelpers;

static if (defined!"DEF")
{
__gshared int a;
}
static if (!defined!"DEF")
{
alias a = int;
}
int f()
{
	int b;
	return mixin((defined!"DEF") ? q{
        	2*(a)-b
    	} : q{
        2*cast(a)-b
    	});
}

