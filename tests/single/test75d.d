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
    struct S;
	}
	static if (!defined!"DEF")
	{
    	S* s;
	}
}

void f(
/+ #ifdef DEF +/
Identity!(mixin((defined!"DEF")?q{S}:q{X.S}))*
/+ #else +/

/+ #endif +/
 s)
{
	X x;
	x.s = s;
}

