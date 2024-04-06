module test240;

import config;
import cppconvhelpers;

enum E
{
	E1,
	E2,
	E3,
	E_LAST
}

__gshared const(int)[E.E_LAST] data = mixin(buildStaticArray!(q{const(int)}, E.E_LAST, q{1, 2, 3}));

