#define test_a(x) 2*x
#define test_b(x) 3*x
#define f(name, y) test_ ## name (y)

int i1 = f(a, 10);
int i2 = f(b, 20);

// tags: higher-order-macro
