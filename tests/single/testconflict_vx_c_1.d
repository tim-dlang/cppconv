module testconflict_vx_c_1;

import config;
import cppconvhelpers;

alias T = int;
alias X = int;

struct S
{
	/+ #ifdef DEF +/
	static if (defined!"DEF")
	{
    	this
    		/+ #endif +/
    		(.X);
	}
	else
	{
    T X;
	}
}

