module testtypedef4;

import config;
import cppconvhelpers;

struct S
{
	int i;
}

/+ #ifdef DEF +/

/+ #endif +/
alias T = Identity!(mixin((defined!"DEF")?q{const(S)}:q{S}))*

;

void test(T){}

