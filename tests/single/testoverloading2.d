module testoverloading2;

import config;
import cppconvhelpers;

int f(int);
char f(char);

void g()
{
	static if (defined!"DEF")
	{
    	int x = 42;
	}
	else
	{
    	char x = 42;
	}

	f(x);
}

