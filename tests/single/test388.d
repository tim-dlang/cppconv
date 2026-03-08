
module test388;

import config;
import cppconvhelpers;

struct S
{
    /+ template<class T> +/
    bool f(T)()
    {
        return true;
    }
    /+ template<class T> +/
    S* f2(T)()
    {
        return &this;
    }
}

/+ #ifdef DEF
#define NAME f
#else
#define NAME f2
#endif +/

static if (defined!"DEF")
{
/+ #define NAME2 p +/
enum NAME2 = q{p};
}
static if (!defined!"DEF")
{
/+ #define NAME2 arr +/
enum NAME2 = q{arr};
}

int main()
{
    S x;
    S[2] arr;
    S* p = &x;
    x.f!(S)();
    p.f!(S)();
    arr[0].f!(S)();
    x.f2!(S)().f!(S)();
    mixin(q{x.
}
~ (defined!"DEF" ? q{
/+ NAME +/f
}:"")
~ (!defined!"DEF" ? q{
f2
}:"")
~ q{
!(S)
}
)();
    mixin(q{
}
~ (defined!"DEF" ? q{
mixin(NAME2)
}:"")
~ (!defined!"DEF" ? q{
mixin(NAME2)
}:"")
~ (!defined!"DEF" ? "[0]":"")
~ q{
.f!(S)
}
)();
    return 0;
}

