module test87;

import config;
import cppconvhelpers;

void f()
{
	for(int i=0; i<10; /+ ( +/i/+ ) +/++){}
}

