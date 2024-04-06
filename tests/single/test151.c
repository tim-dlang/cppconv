static char buf1[4];
static char buf2[] = "test";
static char buf3[4] = "test";

extern int printf (const char *__restrict __format, ...);

int main(void)
{
	printf("sizeof buf1 %zd\n", sizeof buf1);
	printf("sizeof buf2 %zd\n", sizeof buf2);
	printf("sizeof buf3 %zd\n", sizeof buf3);
	printf("sizeof \"test\" %zd\n", sizeof "test");
	printf("sizeof(\"test\") %zd\n", sizeof("test"));
	return 0;
}

