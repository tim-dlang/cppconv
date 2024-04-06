#ifdef DEF
int g(int b, int a);
#define f g
#else
int f(int a, int b);
#endif

int h(int a)
{
	/*commentb1*/return/*commentb2*/f/*commentb3*/(a/*commentb4*/,/*commentb5*/2/*commentb6*/)/*commentb7*/;/*commentb8*/
}
