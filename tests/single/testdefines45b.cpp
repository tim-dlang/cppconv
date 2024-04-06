static int counter;

#ifdef DEF
#define S do \
	{ \
		counter++; \
	} while(0)

#define F(i) do \
	{ \
		int tmp = i; \
		i = tmp * 4 + tmp; \
	} while(0)

#else

#define S do \
	{ \
		counter--; \
	} while(0)

#define F(i) do \
	{ \
		int tmp = i; \
		i = tmp * 5 - tmp; \
	} while(0)

#endif

void g()
{
	S;
	int x;
	F(x);
}
