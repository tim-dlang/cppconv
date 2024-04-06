#define SORT_CONCAT(x, y) x ## _ ## y
#define SORT_MAKE_STR1(x, y) SORT_CONCAT(x,y)
#define SORT_MAKE_STR(x) SORT_MAKE_STR1(SORT_NAME,x)

#define F1          SORT_MAKE_STR(f1)
#define F2          SORT_MAKE_STR(f2)

static int F1(int i)
{
	return i + 1;
}
static int F2(int i)
{
	return i + 2;
}
