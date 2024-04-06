module test281;

import config;
import cppconvhelpers;

extern(C++, class) struct C1
{
public:
	enum E
	{
		E1,
		E2,
		E3
	}
	@disable this();
	/+this()
	{
	    this.i = -1;
	    this.p = null;
	    this.e = E.E3;
	}+/
private:
	int i = -1;
	void* p = null;
	E e = E.E3;
}

extern(C++, class) struct C2
{
public:
	enum E
	{
		E1,
		E2,
		E3
	}
	@disable this();
	/+this()
	{
	    this.i = -2;
	    this.p = null;
	    this.e = E.E2;
	}+/
private:
	int i = -2;
	void* p = null;
	E e = E.E2;
}

