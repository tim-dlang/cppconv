module test19;

import config;
import cppconvhelpers;

__gshared int test =
/+ #ifdef DEF +/
mixin((defined!"DEF") ? q{
        1
    } : q{
        /+ #else +/
        2
    })/+ #endif +/
;
__gshared int test2 =
/+ #ifdef DEF +/
mixin((defined!"DEF") ? q{
        1
    } : q{
        /+ #else +/
        -1
    })/+ #endif +/
;

