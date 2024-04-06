module test294;

import config;
import cppconvhelpers;

class C1
{
public:
	this(int i)
	{
	}
	this()
	{
	    this(0);
	}
	/+ virtual +/~this() {}
}

class C2 : C1
{
public:
	this(int i)
	{
	    super(i);
	}
	this()
	{
	    this(0);
	}
	/+ virtual +/~this() {}
}

struct S1
{
public:
	this(int i)
	{
	}
	@disable this();
	/+this()
	{
	    this(0);
	}+/
}

struct S2
{
    public S1 base0;
    alias base0 this;
public:
	this(int i)
	{
	    this.base0 = S1(i);
	}
	@disable this();
	/+this()
	{
	    this(0);
	}+/
}

