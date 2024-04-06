module testtypedef2;

import config;
import cppconvhelpers;

struct generated_testtypedef2_0
{
	int i;
}
static if (defined!"DEF")
{
alias S = generated_testtypedef2_0
/+ #ifdef DEF +/

/+ #endif +/
;
}
static if (!defined!"DEF")
{
alias T = generated_testtypedef2_0;
}
static if (!defined!"DEF")
{
alias S = T;
}

void test(S){}

alias X = S;

void test2(X){}

