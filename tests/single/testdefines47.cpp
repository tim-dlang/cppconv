#define g(x) x
#define h(x) x
#define f1(x) x
#define f2(x) g(x)
#define f3(x) h(g(x))
int test1 = f1(g(1));
int test2 = f2(2);
int test3 = f2(h(3));
int test4 = f3(4);
int test5 = f3(g(5));
