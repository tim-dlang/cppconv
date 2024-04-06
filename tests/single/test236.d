module test236;

import config;
import cppconvhelpers;

abstract class A
{
public:
	final void f();
	/+ virtual +/ void g();
	/+ friend void h(); +/
	final void i() const;
	/+ virtual +/ void j() const;
	/+ virtual +/ abstract void k(int i=5);
}

class B: A
{
public:
	override void g();
	/+ virtual +/ override void j() const;
	/+ virtual +/ override void k(int i=5);
}

