module testdefines45;

import config;
import cppconvhelpers;

extern(D) static __gshared int counter;

/+ #define S do \
	{ \
		counter++; \
	} while(0) +/
enum S = q{do
    	{
    		counter++;
    	} while(0);};

/+ #define F(i) do \
	{ \
		int tmp = i; \
		i = tmp * 4 + tmp; \
	} while(0) +/
extern(D) alias F = function string(string i)
{
    return mixin(interpolateMixin(q{do
        	{
        		int tmp = $(i);
        		$(i) = tmp * 4 + tmp;
        	} while(0);}));
};

void g()
{
	mixin(S);
	int x;
	mixin(F(q{x}));
}

