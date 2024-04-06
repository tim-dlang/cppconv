module test23;

import config;
import cppconvhelpers;

struct S
{
	int i;
	extern(D) static __gshared const(int) x = 2;
}
__gshared S f = S(S.x);

