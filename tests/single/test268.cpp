long long f();
int f2();

void g()
{
	int i = int(f());
	int i2 = int(f2());
}

inline int qRound(double d)
{ return d >= 0.0 ? int(d + 0.5) : int(d - double(int(d-1)) + 0.5) + int(d-1); }

typedef long long qint64;
inline qint64 qRound64(double d)
{ return d >= 0.0 ? qint64(d + 0.5) : qint64(d - double(qint64(d-1)) + 0.5) + qint64(d-1); }

inline int qIntCast(double f) { return int(f); }

typedef int T1;
typedef T1 T2;
typedef T2 T3;

void h()
{
	long long l;
	int i;
	T3 x1 = T3(l);
	T3 x2 = T3(i);
}
