module testsymbol2;

import config;
import cppconvhelpers;

alias T = long;

struct S
{
	alias T__1 = int;
}

__gshared S.T__1 x;

