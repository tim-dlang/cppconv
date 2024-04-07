module testdefines45b;

import config;
import cppconvhelpers;

extern(D) static __gshared int counter;

static if (defined!"DEF")
{
/+ #define S do \
	{ \
		counter++; \
	} while(0) +/
enum S = q{do
    	{
    		imported!q{testdefines45b}.counter++;
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

}
static if (!defined!"DEF")
{

/+ #define S do \
	{ \
		counter--; \
	} while(0) +/
enum S = q{do
    	{
    		imported!q{testdefines45b}.counter--;
    	} while(0);};

/+ #define F(i) do \
	{ \
		int tmp = i; \
		i = tmp * 5 - tmp; \
	} while(0) +/
extern(D) alias F = function string(string i)
{
    return mixin(interpolateMixin(q{do
        	{
        		int tmp = $(i);
        		$(i) = tmp * 5 - tmp;
        	} while(0);}));
};

}

void g()
{
	static if (defined!"DEF")
	{
    	mixin(S);
	}
	else
	{
    mixin(S);
	}

	int x;
	static if (defined!"DEF")
	{
    	mixin(F(q{x}));
	}
	else
	{
    mixin(F(q{x}));
	}

}

