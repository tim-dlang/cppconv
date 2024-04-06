
module test68b;

import config;
import cppconvhelpers;

void f1(char* s);
void f2(const(char)* s);
void f3(void* s);
void f4(const(void)* s);
void g()
{
	char[2] s = ['a', '\0'];
	f1(s.ptr);
	f2(s.ptr);
	f3(s.ptr);
	f4(s.ptr);
	/+ const(char)[0]  +/ auto s2 = mixin(buildStaticArray!(q{const(char)}, q{'a', '\0'}));
	//f1(s2);
	f2(s2.ptr);
	//f3(s2);
	f4(s2.ptr);
	void* s3 = s.ptr;
	f1(cast(char*) (s3));
	f2(cast(const(char)*) (s3));
	f3(s3);
	f4(s3);
}

