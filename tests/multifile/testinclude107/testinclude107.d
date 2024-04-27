module testinclude107;

import config;
import cppconvhelpers;

static if (defined!"DEF")
{
static if (defined!"DEF2")
{
struct S
{

}
}
static if (!defined!"DEF2")
{
struct S2
{

}
/+ #define S S2 +/
alias S = S2;
}
}

