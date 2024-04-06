#ifdef DEF
typedef int Point[2];
#else
struct Point
{
	int x;
	int y;
};
#endif

typedef Point P;

P point1 = {1, 2};
P points[] = {{1, 2}, {3, 4}, {5, 6}};
