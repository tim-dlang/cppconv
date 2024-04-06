module test316;

import config;
import cppconvhelpers;

enum E
{
	X,
	Y
}

E f()
{
	return cast(E) (1);
}

extern(C++, "N")
{
enum E2
{
	X2,
	Y2
}
}

/+ N:: +/E2 f2()
{
	return cast(/+ N:: +/E2) (1);
}

