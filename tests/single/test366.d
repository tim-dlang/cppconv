
module test366;

import config;
import cppconvhelpers;

struct S_
{
  uint NU;
}
alias S = S_;

static if (defined!"DEF")
{

  /+ #ifdef DEF +/
    alias Ref = S_*
  /+ #else
    unsigned
  #endif +/
;
}
static if (!defined!"DEF")
{
alias Ref = uint;
}

static if (defined!"DEF")
{
  /+ #define NODE(ptr) (ptr) +/
extern(D) alias NODE = function string(string ptr)
{
    return mixin(interpolateMixin(q{($(ptr))}));
};
}
static if (!defined!"DEF")
{
  /+ #define NODE(offs) ((S *)(p->Base + (offs))) +/
extern(D) alias NODE = function string(string offs)
{
    return mixin(interpolateMixin(q{(cast(imported!q{test366}.S*)(p.Base + ($(offs))))}));
};
}

struct X
{
  ubyte*  Base;
}
// self alias: alias X = X;


void f(X* p, Ref n)
{
    S* node = mixin((defined!"DEF") ? q{
            mixin(NODE(q{n}))
        } : q{
        mixin(NODE(q{n}))
        });
    uint nu = cast(uint)node.NU;
    S* node2 = mixin((defined!"DEF") ? q{
            mixin(NODE(q{n}))
        } : q{
        mixin(NODE(q{n}))
        }) + nu;
}

