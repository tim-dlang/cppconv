int g(int);
#define f1(x) (x + 3)
int test = f1(f1(f1(42)));
#define X f1(f1(f1(43)))
int test2 = X;
#define Y() f1(f1(f1(44)))
int test3 = Y();
