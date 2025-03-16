module testsymbol2;

import config;
import cppconvhelpers;

alias T = long;

struct S
{
	alias T = int;
}

__gshared S.T x;

