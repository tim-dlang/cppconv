module testsymbol9;

import config;
import cppconvhelpers;

extern(C++, class) struct A
{
public:
	/+
	extern(C++, class) struct C;
	+/extern(C++, class) struct C
	{
	public:
		alias D = int;
	}

}

extern(C++, class) struct B
{
public:
	A.C f();
}

__gshared A.C.D d;

