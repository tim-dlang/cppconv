static int counter;

#define S do \
	{ \
		counter++; \
	} while(0)

#define F(i) do \
	{ \
		int tmp = i; \
		i = tmp * 4 + tmp; \
	} while(0)

void g()
{
	S;
	int x;
	F(x);
}
