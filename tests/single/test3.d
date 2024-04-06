module test3;

import config;
import cppconvhelpers;

/+ #ifdef DEF1 +/
static if (defined!"DEF2")
{
Identity!(mixin((defined!"DEF1")?q{int}:q{double}))
/+ #else +/

/+ #endif
#ifdef DEF2 +/
func(int param1,
/+ #else
func2(double param1,
#endif
#ifdef DEF3 +/
mixin((defined!"DEF3") ? q{int } : q{AliasSeq!()}) param2,
/+ #else +/
mixin((!defined!"DEF3") ? q{double } : q{AliasSeq!()}) param2
/+ #endif +/
);
}
static if (!defined!"DEF2")
{
Identity!(mixin((defined!"DEF1")?q{int}:q{double})) func2(double param1, mixin((defined!"DEF3") ? q{int} : q{AliasSeq!()}) param2, mixin((!defined!"DEF3") ? q{double} : q{AliasSeq!()}) param2);
}

