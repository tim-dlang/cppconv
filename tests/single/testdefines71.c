const int g = 1;
#define f(x) x
#define X (1*g)
int i = f(X) + 1;

#define Y X
int i2 = Y;

#define f2(y) f(y)
int i3 = f2(X) + 3;
