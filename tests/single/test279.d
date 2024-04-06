module test279;

import config;
import cppconvhelpers;

void f()
{
	int i = 0;
	
	{

    	scope(failure)
    	{
    		i = 5;
    	}
		i = 2;
	}
}

