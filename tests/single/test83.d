module test83;

import config;
import cppconvhelpers;

void test();
void f(int x)
{
	switch(x)
	{
		case 1:
		case 2:
		case 3:
		test();
		test();
		test();
		break;
		case 4:
		return;
		case 5:goto default;
default:

	}
}
void f2(int x)
{
	switch(x)
	{
		case 1:
		case 2:
		case 3:
		test();
		test();
		test();
		break;
		case 4:
		return;
		default:
	}
}

