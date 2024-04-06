module test329;

import config;
import cppconvhelpers;

extern(C++, class) struct C
{
private:
	extern(D) static immutable uint Constant = 1;
}

