module testconflict_md_s_1;

import config;
import cppconvhelpers;

static if (defined!"DEF")
{
extern(C++, class) struct a
{
}
__gshared a* c;
}
static if (!defined!"DEF")
{
struct S
{
    ref S opBinary(string op)(S) if (op == "*")
    {
        return this;
    }
    /+ explicit +/ auto opCast(T : bool)() const
    {
        return true;
    }
}
__gshared S a;
 __gshared S b;
  __gshared S c;
}
void f()
{
    mixin(q{if (
    }
    ~ (!defined!"DEF" ? q{
    (){return a *.b = c;
    }()
    }:"")
    ~ (defined!"DEF" ? q{
    a* b__1=c
    }:"")
    ~ q{
    )
        {}
}
);}

