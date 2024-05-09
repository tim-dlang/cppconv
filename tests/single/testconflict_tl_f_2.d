module testconflict_tl_f_2;

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

void f2(T)(int i1, int i2, T param, int i4, int i5)
{}
void f2(T)(int i1, int i2, T param, T param2, int i4, int i5)
{}

void f()
{
	const(int) a = 2;
	const(int) b = 2;
	const(int) c = 2;
	(mixin(q{f2
    }
    ~ "("
    ~ q{
        1, 2,
    }
    ~ (!defined!"DEF" ? q{
         T1!(a, b) (c)
    }:"")
    ~ (defined!"DEF" ? q{
        T1<a,b>(c)
    }:"")
    ~ q{
        , 4, 5
    }
    ~ ")"
));
}

