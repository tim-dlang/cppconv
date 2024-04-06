module testtypedef3;

import config;
import cppconvhelpers;

struct generated_testtypedef3_0
{
	int i;
}

/+ #ifdef DEF +/

/+ #endif +/
alias S = Identity!(mixin((defined!"DEF")?q{const(generated_testtypedef3_0)}:q{generated_testtypedef3_0}))

;

void test(S){}

