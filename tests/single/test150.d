module test150;

import config;
import cppconvhelpers;

int printf (const(char)*/+ __restrict +/  __format, ...);

void f1()
{
	struct _alone_header {
	    ubyte[5]  bytes;
	    ulong   uncompressed_size;
	}_alone_header alone_header;

	printf("sizeof(struct _alone_header) %zd\n", _alone_header.sizeof);
	printf("sizeof alone_header %zd\n",  alone_header. sizeof);
	printf("sizeof offset bytes[0] %zd\n", cast(void*)&alone_header.bytes[0] - cast(void*)&alone_header);
	printf("sizeof offset uncompressed_size %zd\n", cast(void*)&alone_header.uncompressed_size - cast(void*)&alone_header);
}

void f2()
{
/+ #pragma pack(push)
#pragma pack(1) +/
	struct _alone_header2 {
	align(1):
	    ubyte[5]  bytes;
	    ulong   uncompressed_size;
	}_alone_header2 alone_header2;
/+ #pragma pack(pop) +/

	printf("sizeof(struct _alone_header2) %zd\n", _alone_header2.sizeof);
	printf("sizeof alone_header2 %zd\n",  alone_header2. sizeof);
	printf("sizeof offset bytes[0] %zd\n", cast(void*)&alone_header2.bytes[0] - cast(void*)&alone_header2);
	printf("sizeof offset uncompressed_size %zd\n", cast(void*)&alone_header2.uncompressed_size - cast(void*)&alone_header2);
}

void f3()
{
/+ _Pragma("pack(push)")
_Pragma("pack(1)") +/
	struct _alone_header3 {
	align(1):
	    ubyte[5]  bytes;
	    ulong   uncompressed_size;
	}_alone_header3 alone_header3;
/+ _Pragma("pack(pop)") +/

	printf("sizeof(struct _alone_header3) %zd\n", _alone_header3.sizeof);
	printf("sizeof alone_header3 %zd\n",  alone_header3. sizeof);
	printf("sizeof offset bytes[0] %zd\n", cast(void*)&alone_header3.bytes[0] - cast(void*)&alone_header3);
	printf("sizeof offset uncompressed_size %zd\n", cast(void*)&alone_header3.uncompressed_size - cast(void*)&alone_header3);
}

void f4()
{
	struct _alone_header4 {
	    ubyte[5]  bytes;
	    ulong   uncompressed_size;
	}_alone_header4 /+ __attribute__ ((packed)) +/ alone_header4;

	printf("sizeof(struct _alone_header4) %zd\n", _alone_header4.sizeof);
	printf("sizeof alone_header4 %zd\n",  alone_header4. sizeof);
	printf("sizeof offset bytes[0] %zd\n", cast(void*)&alone_header4.bytes[0] - cast(void*)&alone_header4);
	printf("sizeof offset uncompressed_size %zd\n", cast(void*)&alone_header4.uncompressed_size - cast(void*)&alone_header4);
}

void f5()
{
	struct /+ __attribute__ ((packed)) +/ _alone_header5 {
	    ubyte[5]  bytes;
	    /+ __attribute__ ((aligned (2))) +/ ulong   uncompressed_size;
	}_alone_header5 alone_header5;

	printf("sizeof(struct _alone_header5) %zd\n", _alone_header5.sizeof);
	printf("sizeof alone_header5 %zd\n",  alone_header5. sizeof);
	printf("sizeof offset bytes[0] %zd\n", cast(void*)&alone_header5.bytes[0] - cast(void*)&alone_header5);
	printf("sizeof offset uncompressed_size %zd\n", cast(void*)&alone_header5.uncompressed_size - cast(void*)&alone_header5);
}

void f6()
{
	struct _alone_header6 {
	    ubyte[5]  bytes;
	    /+ __attribute__ ((packed, aligned (2))) +/ ulong   uncompressed_size;
	}_alone_header6 alone_header6;

	printf("sizeof(struct _alone_header6) %zd\n", _alone_header6.sizeof);
	printf("sizeof alone_header6 %zd\n",  alone_header6. sizeof);
	printf("sizeof offset bytes[0] %zd\n", cast(void*)&alone_header6.bytes[0] - cast(void*)&alone_header6);
	printf("sizeof offset uncompressed_size %zd\n", cast(void*)&alone_header6.uncompressed_size - cast(void*)&alone_header6);
}

int main()
{
	f1();
	f2();
	f3();
	f4();
	f5();
	f6();
	return 0;
}

