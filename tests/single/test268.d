module test268;

import config;
import cppconvhelpers;

long  f();
int f2();

void g()
{
	int i = cast(int) (f());
	int i2 = int(f2());
}

pragma(inline, true) int qRound(double d)
{ return d >= 0.0 ? cast(int) (d + 0.5) : cast(int) (d - double(cast(int) (d-1)) + 0.5) + cast(int) (d-1); }

alias qint64 = long;
pragma(inline, true) qint64 qRound64(double d)
{ return d >= 0.0 ? cast(qint64) (d + 0.5) : cast(qint64) (d - double(cast(qint64) (d-1)) + 0.5) + cast(qint64) (d-1); }

pragma(inline, true) int qIntCast(double f__1) { return cast(int) (f__1); }

alias T1 = int;
alias T2 = T1;
alias T3 = T2;

void h()
{
	long  l;
	int i;
	T3 x1 = cast(T3) (l);
	T3 x2 = T3(i);
}

