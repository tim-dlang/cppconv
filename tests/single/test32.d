module test32;

import config;
import cppconvhelpers;

static if (defined!"DEF")
{
struct S
{
	int i;
	void f()
	{
		int x;
	}
	struct Inner
	{
		int x;int y;
	}Inner d;
	int different1;
}
}
static if (!defined!"DEF")
{
struct S
{
	int i;
	void f()
	{
		int x;
	}
	struct Inner
	{
		int x;int y;
	}Inner d;
	int different2;
}
}

