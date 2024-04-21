module test365;

import config;
import cppconvhelpers;

__gshared const(char)* s1 = mixin(((!defined!"DEF1" && !defined!"DEF2")) ? q{
        "prefix"
    } : q{
        "prefix"~ mixin((defined!"DEF1") ? q{
                        "_suffix1"
            } : q{
                "_suffix2"
            })
    });
__gshared const(char)* s2 =
/+ #ifdef DEF1 +/
mixin(((!defined!"DEF1" && !defined!"DEF2")) ? q{
        /+ "prefix1_"
        #elif defined(DEF2)
        "prefix2_"
        #endif +/
        "suffix"
    } : q{
        mixin((defined!"DEF1") ? q{
                        "prefix1_"
            } : q{
                "prefix2_"
            })~ "suffix"
    });
__gshared const(char)* s3 = "pre" ~ "fix"~ 
mixin((defined!"DEF1") ? q{
        "_suffix1"
    } : ((!defined!"DEF1" && defined!"DEF2")) ? q{
        "_suffix2"
    } : q{
        ""
    });
__gshared const(char)* s4 =
/+ #ifdef DEF1 +/
mixin((defined!"DEF1") ? q{
        "prefix1_"
    } : ((!defined!"DEF1" && defined!"DEF2")) ? q{
        /+ #elif defined(DEF2) +/
        "prefix2_"
    } : q{
        /+ #endif +/
        "suf"
    })~ mixin(((defined!"DEF1" || defined!"DEF2")) ? q{
            "suf"
        } : q{
        ""
        }) ~ "fix"
;
__gshared const(char)* s5 = "prefix_"~ 
mixin((defined!"DEF1") ? q{
        "middle1"
    } : ((!defined!"DEF1" && defined!"DEF2")) ? q{
        "middle2"
    } : q{
        ""
    })~ "_suffix"
;

