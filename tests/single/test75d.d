module test75d;

import config;
import cppconvhelpers;

static if (defined!"DEF")
{
struct S;
}
struct X
{
	static if (defined!"DEF")
	{
    	.S*
    		/+ #ifdef DEF +/
    		s
    		/+ #endif +/
    		;
	}
	else
	{
    struct S__1;
	}
	static if (!defined!"DEF")
	{
    	S__1* s;
	}
}

void f(
/+ #ifdef DEF +/
Identity!(mixin((defined!"DEF")?q{S}:q{X.S__1}))*
/+ #else +/

/+ #endif +/
 s)
{
	X x;
	x.s = s;
}

