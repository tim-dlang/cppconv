module testtypedef6;

import config;
import cppconvhelpers;


/+ #ifdef DEF +/
alias X = Identity!(mixin((defined!"DEF")?q{int}:q{float}))
/+ #else +/

/+ #endif +/
;

alias Y = X;

alias Z = Y;

void test(Z){}

