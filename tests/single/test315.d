module test315;

import config;
import cppconvhelpers;

struct S
{
	S f() const/+ &+/;
	/+ S f() &&; +/
}

