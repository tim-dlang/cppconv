// based on testinclude75.h
#ifdef DEF
#define SORT_NAME2 x
#endif
#define SORT_CONCAT(x, y) x ## _ ## y
#define SORT_MAKE_STR1(x, y) SORT_CONCAT(x,y)
#define SORT_MAKE_STR(x) SORT_MAKE_STR1(SORT_NAME2,x)

#define F1          SORT_MAKE_STR(f1)

static int F1(int i)
{
	return i + 1;
}
