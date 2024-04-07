module test93;

import config;
import cppconvhelpers;

/+ #ifdef DEF
#define DEBUG_PARAMS1 , const char *function , unsigned line
#define DEBUG_PARAMS2 , __FUNCTION__ , __LINE__
#else
#define DEBUG_PARAMS1
#define DEBUG_PARAMS2
#endif +/

void f_(int i /+ DEBUG_PARAMS1 +/, mixin((defined!"DEF") ? q{const(char)*} : q{AliasSeq!()}) function_, mixin((defined!"DEF") ? q{uint} : q{AliasSeq!()}) line);
/+ #define f(i) f_(i DEBUG_PARAMS2) +/
extern(D) alias f = function string(string i)
{
    return mixin(interpolateMixin(q{(mixin(q{imported!q{test93}.f_
            }
            ~ "("
            ~ q{
                $(i)
            }
            ~ (defined!"DEF" ? q{
                 /+ DEBUG_PARAMS2 +/,__FUNCTION__,__LINE__
            }:"")
            ~ ")"
        ))}));
};

void g()
{
	(mixin(f(q{5})));
}

