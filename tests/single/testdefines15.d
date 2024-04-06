module testdefines15;

import config;
import cppconvhelpers;

int g()
{
	return 1;
}
int g2(int i)
{
	return i;
}
/+ #define f1() ) +/
__gshared int x1 = g(/+ f1() +/);
/+ #define f2() g( +/
__gshared int x2 = /+ f2() +/g();
/+ #define f3() ( +/
__gshared int x3 = g /+ f3() +/( );
/+ #define f4() () +/
__gshared int x4 = g /+ f4() +/();
/+ #define f5() (((( +/
__gshared int x5 = g2 /+ f5() +/(((( 1 ))));

