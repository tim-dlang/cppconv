int g()
{
	return 1;
}
int g2(int i)
{
	return i;
}
#define f1() )
int x1 = g(f1();
#define f2() g(
int x2 = f2());
#define f3() (
int x3 = g f3() );
#define f4() ()
int x4 = g f4();
#define f5() ((((
int x5 = g2 f5() 1 ))));
