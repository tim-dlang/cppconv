extern int printf (const char *__restrict __format, ...);

static void f1(void)
{
	struct _alone_header {
	    unsigned char bytes[5];
	    unsigned long long uncompressed_size;
	} alone_header;

	printf("sizeof(struct _alone_header) %zd\n", sizeof(struct _alone_header));
	printf("sizeof alone_header %zd\n", sizeof alone_header);
	printf("sizeof offset bytes[0] %zd\n", (void*)&alone_header.bytes[0] - (void*)&alone_header);
	printf("sizeof offset uncompressed_size %zd\n", (void*)&alone_header.uncompressed_size - (void*)&alone_header);
}

static void f2(void)
{
#pragma pack(push)
#pragma pack(1)
	struct _alone_header2 {
	    unsigned char bytes[5];
	    unsigned long long uncompressed_size;
	} alone_header2;
#pragma pack(pop)

	printf("sizeof(struct _alone_header2) %zd\n", sizeof(struct _alone_header2));
	printf("sizeof alone_header2 %zd\n", sizeof alone_header2);
	printf("sizeof offset bytes[0] %zd\n", (void*)&alone_header2.bytes[0] - (void*)&alone_header2);
	printf("sizeof offset uncompressed_size %zd\n", (void*)&alone_header2.uncompressed_size - (void*)&alone_header2);
}

static void f3(void)
{
_Pragma("pack(push)")
_Pragma("pack(1)")
	struct _alone_header3 {
	    unsigned char bytes[5];
	    unsigned long long uncompressed_size;
	} alone_header3;
_Pragma("pack(pop)")

	printf("sizeof(struct _alone_header3) %zd\n", sizeof(struct _alone_header3));
	printf("sizeof alone_header3 %zd\n", sizeof alone_header3);
	printf("sizeof offset bytes[0] %zd\n", (void*)&alone_header3.bytes[0] - (void*)&alone_header3);
	printf("sizeof offset uncompressed_size %zd\n", (void*)&alone_header3.uncompressed_size - (void*)&alone_header3);
}

static void f4(void)
{
	struct _alone_header4 {
	    unsigned char bytes[5];
	    unsigned long long uncompressed_size;
	} __attribute__ ((packed)) alone_header4;

	printf("sizeof(struct _alone_header4) %zd\n", sizeof(struct _alone_header4));
	printf("sizeof alone_header4 %zd\n", sizeof alone_header4);
	printf("sizeof offset bytes[0] %zd\n", (void*)&alone_header4.bytes[0] - (void*)&alone_header4);
	printf("sizeof offset uncompressed_size %zd\n", (void*)&alone_header4.uncompressed_size - (void*)&alone_header4);
}

static void f5(void)
{
	struct __attribute__ ((packed)) _alone_header5 {
	    unsigned char bytes[5];
	    __attribute__ ((aligned (2))) unsigned long long uncompressed_size;
	} alone_header5;

	printf("sizeof(struct _alone_header5) %zd\n", sizeof(struct _alone_header5));
	printf("sizeof alone_header5 %zd\n", sizeof alone_header5);
	printf("sizeof offset bytes[0] %zd\n", (void*)&alone_header5.bytes[0] - (void*)&alone_header5);
	printf("sizeof offset uncompressed_size %zd\n", (void*)&alone_header5.uncompressed_size - (void*)&alone_header5);
}

static void f6(void)
{
	struct _alone_header6 {
	    unsigned char bytes[5];
	    __attribute__ ((packed, aligned (2))) unsigned long long uncompressed_size;
	} alone_header6;

	printf("sizeof(struct _alone_header6) %zd\n", sizeof(struct _alone_header6));
	printf("sizeof alone_header6 %zd\n", sizeof alone_header6);
	printf("sizeof offset bytes[0] %zd\n", (void*)&alone_header6.bytes[0] - (void*)&alone_header6);
	printf("sizeof offset uncompressed_size %zd\n", (void*)&alone_header6.uncompressed_size - (void*)&alone_header6);
}

int main(void)
{
	f1();
	f2();
	f3();
	f4();
	f5();
	f6();
	return 0;
}

