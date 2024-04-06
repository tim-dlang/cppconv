module test176;

import config;
import cppconvhelpers;

int f(int);
__gshared int function(int) fp;

void g()
{
	if(fp == &f)
	{
	}
}

