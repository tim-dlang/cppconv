module testdefines46;

import config;
import cppconvhelpers;

void f();
void f3(int);

static if (defined!"DEF")
{
/+ #define F1 f(); +/
/+ #define F2 f() +/
enum F2 = q{f()};
/+ #define F3(i) f3(i); +/
/+ #define F4(i) f3(i) +/
extern(D) alias F4 = function string(string i)
{
    return mixin(interpolateMixin(q{f3($(i));}));
};
}
static if (!defined!"DEF")
{
/+ #define F1
#define F2
#define F3(i)
#define F4(i) +/
}

void g1a()
{
	static if (defined!"DEF")
	{
    	/+ F1 +/
    f();
	}
}
int g1b()
{
	int i;
	static if (defined!"DEF")
	{
    	/+ F1 +/
    f();
	}
	return i;
}
void g2a()
{
	static if (defined!"DEF")
	{
    	(mixin(F2));
	}
	else
	{
	}
}
int g2b()
{
	int i;
	static if (defined!"DEF")
	{
    	(mixin(F2));
	}
	else
	{
	}
	return i;
}
void g3a(int i)
{
	static if (defined!"DEF")
	{
    	/+ F3(i) +/
    f3(i);
	}
}
int g3b()
{
	int i;
	static if (defined!"DEF")
	{
    	/+ F3(i) +/
    f3(i);
	}
	return i;
}
void g4a(int i)
{
	static if (defined!"DEF")
	{
    	mixin(F4(q{i}));
	}
	else
	{

	}
}
int g4b()
{
	int i;
	static if (defined!"DEF")
	{
    	mixin(F4(q{i}));
	}
	else
	{

	}
	return i;
}

/+ #define L(x) do {x} while(0); +/
extern(D) alias L = function string(string x)
{
    return mixin(interpolateMixin(q{do {/+ x +/} while(0);}));
};
extern(D) alias L__1 = function string(string x)
{
    return mixin(interpolateMixin(q{do {$(x)} while(0);}));
};
void g5()
{
	mixin(L(q{}));
	mixin(L__1(q{f();}));
}

