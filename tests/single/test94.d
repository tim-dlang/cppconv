module test94;

import config;
import cppconvhelpers;

static if (defined!"DEF")
{
	/+ #define i x +/
}
static if (!defined!"DEF")
{
	/+ #define i y +/
}
struct S
{
	static if (defined!"DEF")
	{
    	int x;
		/+ #define i x +/
	}
	else
	{
    	int y;
		/+ #define i y +/
	}
}

int f(S* s)
{
	return mixin(q{s
}
 ~ ((defined!"DEF") ? ".x" : ".y"));
}

