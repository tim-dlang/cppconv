// defined has special meaning inside #if-expressions
// make sure those don't conflict with normal code.
int defined(int i)
{
	return i;
}
int i1 = defined(3);
#define X defined(4)
int i2 = X;
#define f(x) defined(x)
int i3 = f(5);
#define Y f(6)
int i4 = Y;
#define g() X
int i5 = g();
