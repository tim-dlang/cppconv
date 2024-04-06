module test97;

import config;
import cppconvhelpers;

int f(int i)
{
	int r = 1;
	switch(i)
	{
		case 1:
		r *= 3;
		goto case;
case 2:
		r *= 4;
		goto case;
case 3:
		r *= 5;
		goto default;
default:
		r *= 6;
	}
	return r;
}

