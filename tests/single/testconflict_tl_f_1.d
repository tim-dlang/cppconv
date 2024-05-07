module testconflict_tl_f_1;

import config;
import cppconvhelpers;

static if (defined!"DEF")
{
__gshared const(int) T1 = 1;
}
static if (!defined!"DEF")
{
struct T1(int a, int b)
{
	this(int x){}
}
}

void f2(T)(T param)
{}
void f2(T)(T param, T param2)
{}

void f()
{
	const(int) a = 2;
	const(int) b = 2;
	const(int) c = 2;
	(mixin(q{f2
    }
    ~ "("
    ~ (!defined!"DEF" ? q{
        T1!(a, b) (c)
    }:"")
    ~ (defined!"DEF" ? q{
        T1<a,b>(c)
    }:"")
    ~ ")"
));
}

