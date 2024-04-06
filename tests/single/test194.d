module test194;

import config;
import cppconvhelpers;

void f()
{
	void* s1 = cast(void*) ("s1".ptr);
	void* s2 = cast(void*)"s2".ptr;
	char* s3 = cast(char*) ("s3");
	ubyte*  s4 = cast(ubyte*) ("s4".ptr);
	byte*  s5 = cast(byte*) ("s5".ptr);
	void* s6 = cast(ubyte*)"s6";
}

