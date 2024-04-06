module test230;

import config;
import cppconvhelpers;

extern(C++, class) struct C1
{
public:
	this(int x, int y)
	{
	    this.x = x;
	    this.y = y;
	}

	int x; int y;
}

extern(C++, class) struct C2
{
    public C1 base0;
    alias base0 this;
public:
	this(int x, int y)
	{
	    this.base0 = C1(x, y);
	}
}

extern(C++, class) struct C3
{
public:
	this(int x, int y)
	{
	    this.c1 = typeof(this.c1)(x, y);
	}

	C1 c1;
}

