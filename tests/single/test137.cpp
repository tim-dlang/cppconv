#ifndef DEF
#define	__LA_FALLTHROUGH	__attribute__((fallthrough))
#else
#define	__LA_FALLTHROUGH
#endif

void g();
void f(int level)
{
	switch (level)
	{
	case 4:
		g();
		__LA_FALLTHROUGH;
	case 3:
		g();
		__attribute__((fallthrough));
	case 2:
		g();
		__LA_FALLTHROUGH;
	default:
		g();
	}
}
