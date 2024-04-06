#define f(a, b, c) a ## b ## c

#ifdef DEF
const int test_a = 100;
const int test_b = 200;
#else
#define test_a 1
#define test_b 2
#endif

int i = f(test_, a + test_, b);
