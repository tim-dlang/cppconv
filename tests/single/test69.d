module test69;

import config;
import cppconvhelpers;

struct S
{
	int i;
	double d;
}
__gshared const(S) s = const(S)(2, 3.14);
__gshared /+ const(int)[0]  +/ auto a = mixin(buildStaticArray!(q{const(int)}, q{1, 2}));

