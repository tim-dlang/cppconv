module testsymbol7;

import config;
import cppconvhelpers;

struct S
{
}

alias T1 = /+ :: +/S;

extern(C++, class) struct C
{
private:
	struct S__1
	{
	}
	alias T2 = /+ :: +/.S;
}

