module testoverloading3;

import config;
import cppconvhelpers;

int f(int);
char f(char);

struct S
{
	S* f(int);
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
}

