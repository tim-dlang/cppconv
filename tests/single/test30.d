// FogThesis.pdf 152
// FogThesis.pdf 367
module test30;

import config;
import cppconvhelpers;

static if (defined!"DEF")
{
alias Y = int;
}
static if (!defined!"DEF")
{
alias X = int;
}

static if (defined!"DEF")
{
struct
/+ #ifdef DEF +/
X

/+ #endif +/
{
	this(.Y);
}
}
static if (!defined!"DEF")
{
struct Z{X Y;}
}

