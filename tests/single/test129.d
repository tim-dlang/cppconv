module test129;

import config;
import cppconvhelpers;

int f(int i)
{
	for(int k=i; k < i+10; k++)
	{
		static if (!defined!"DEF")
		{
    		int i__1 = k + 1000;
		}
		return 
mixin(!defined!"DEF" ? q{i__1} : q{i});
	}
	return -1;
}

int main()
{
	f(5);
	return 0;
}

