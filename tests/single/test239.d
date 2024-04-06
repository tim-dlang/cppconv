module test239;

import config;
import cppconvhelpers;

static if (defined!"DEF")
{
alias X1 = int;
/+ #define X X1 +/
}
static if (!defined!"DEF")
{
alias X2 = float;
/+ #define X X2 +/
}

/+ X +/__gshared Identity!(mixin((defined!"DEF")?q{X1}:q{X2})) var;

