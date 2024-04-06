module test293;

import config;
import cppconvhelpers;

extern(C++, class) struct C
{
public:
	this(uint )
	{
	    this.a = 1;
	    this.b = 2;

	}
	this(ulong )
	{
	    this.a = 1;
	    this.b = 2;

		void f();
	}
	this(ushort )
	{
	    this.a = 1;
	    this.b = 2;
	    this.c = 3;
	}
	this(int)
	{
	    this.a = 1;
	    this.b = 2;
	    this.c = 3;
	}
	this(long)
	{
	    this.a = 1;
	    this.b = 2;
	    this.c = 3;
	}
	this(char)
	{
	    this.a = 1;
	    this.b = 2;
	    this.c = 3;
	    f();
	}
	this(short)
	{
	    this.a = 1;
	    this.b = 2;
	    this.c = 3;
	    f();
	}

	int a; int b; int c;

	void f() {}
}

