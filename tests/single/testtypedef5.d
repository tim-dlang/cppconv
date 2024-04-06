module testtypedef5;

import config;
import cppconvhelpers;

static if (defined!"DEF")
{
struct
/+ #ifdef DEF +/
S1

/+ #endif +/
{
	int i;
}
}
static if (!defined!"DEF")
{
struct S2{int i;}
}


/+ #ifdef DEF +/
alias T = Identity!(mixin((defined!"DEF")?q{S1}:q{S2}))
/+ #else +/

/+ #endif +/
;

void test(T){}

