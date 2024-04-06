module test62e;

import config;
import cppconvhelpers;

/+ #ifdef DEF +/
static if (defined!"DEF")
{
enum E
/+ #ifndef DEF
E +/
/+ #endif +/
{
	A,
	B,
	C
}
}
static if (!defined!"DEF")
{
enum E{A,B,C}
}
static if (defined!"DEF")
{

/+ #endif +/
// self alias: alias E = E
/+ #ifdef DEF +/

/+ #endif +/
;
}

void f(E);

void g()
{
	f(E.A);
}

