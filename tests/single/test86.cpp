extern "C"
{
struct S
{
	int test1;

	unsigned test2: 1;
	unsigned test3: 2;
#ifndef DEF
	unsigned test4;
#endif
	unsigned test5: 1;
};

union U
{
	S s;
	unsigned char data[sizeof(S)];
};

extern int printf ( const char * format, ... );
}

#define TEST(name) \
	{ \
		U u; \
		 \
		for(unsigned i=0; i<sizeof(S); i++) \
			u.data[i] = 0; \
		 \
		u.s.name = 1; \
		 \
		printf(#name); \
		for(unsigned i=0; i<sizeof(S); i++) \
			printf(" %02X", u.data[i]); \
		printf("\n"); \
	}

int main()
{
	TEST(test1)
	TEST(test2)
	TEST(test3)
	#ifndef DEF
	TEST(test4)
	#endif
	TEST(test5)

	return 0;
}

