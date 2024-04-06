module testcomments9;

import config;
import cppconvhelpers;

static if (defined!"DEF")
{
int g(int b, int a);
/+ #define f g +/
alias f = g;
}
static if (!defined!"DEF")
{
int f(int a, int b);
}

int h(int a)
{
	/*commentb1*/return/*commentb2*/ mixin((defined!"DEF") ? q{
        	f
    	} : q{
        f
    	})/*commentb3*/(a/*commentb4*/,/*commentb5*/2/*commentb6*/)/*commentb7*/;/*commentb8*/
}

