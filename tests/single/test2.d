module test2;

import config;
import cppconvhelpers;

void f()
{
	int i0=0;
	int i1=1;
	static if (defined!"DEF")
	{
    	int i2a=2;
	}
	else
	{
    	int i2b=2;
	}
	int i3=3;
	int i4=4;
}

