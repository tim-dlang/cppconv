module test314;

import config;
import cppconvhelpers;

extern(C++, class) struct C
{
public:
    char[10] data;
    pragma(inline, true) ref char opIndex(int j) { return data[j]; }
    ref char front()
    {
		return opIndex(0);
	}
}

