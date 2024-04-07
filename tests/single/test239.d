module test239;

import config;
import cppconvhelpers;

static if (defined!"DEF")
{
alias X1 = int;
/+ #define X X1 +/
alias X = X1;
}
static if (!defined!"DEF")
{
alias X2 = float;
/+ #define X X2 +/
alias X = X2;
}

__gshared X var;

