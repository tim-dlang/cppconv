module test151;

import config;
import cppconvhelpers;

extern(D) static __gshared char[4] buf1;
extern(D) static __gshared /+ char[0]  +/ auto buf2 = staticString!(char, "test");
extern(D) static __gshared char[4] buf3 = "test";

int printf (const(char)*/+ __restrict +/  __format, ...);

int main()
{
	printf("sizeof buf1 %zd\n", (  buf1.length ) * char.sizeof);
	printf("sizeof buf2 %zd\n", (  buf2.length ) * char.sizeof);
	printf("sizeof buf3 %zd\n", (  buf3.length ) * char.sizeof);
	printf("sizeof \"test\" %zd\n", (  "test".length + 1 ) * char.sizeof);
	printf("sizeof(\"test\") %zd\n", ( ("test").length + 1 ) * char.sizeof);
	return 0;
}

