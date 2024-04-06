module testsymbol1;

import config;
import cppconvhelpers;

void func();

struct S
{
	void test();
	static void testStatic();
}

void f()
{
	func();
	S s;
	s.test();
	S.testStatic();
}

