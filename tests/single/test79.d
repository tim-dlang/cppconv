module test79;

import config;
import cppconvhelpers;


/+ #ifdef DEF2
struct S;
#endif
#ifdef DEF3
struct S;
#endif
#ifdef DEF4
struct S;
#endif +/

static if (defined!"DEF")
{
struct S
{
	int i;
}
}
static if (!defined!"DEF")
{
struct S
{
	long i;
}
}

/+ #ifdef DEF5
struct S;
#endif
#ifdef DEF6
struct S;
#endif
#ifdef DEF7
struct S;
#endif +/

