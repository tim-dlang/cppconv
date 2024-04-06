
#ifdef DEF
typedef int x;
#else
const int x = 0;
#endif

const int y = 1;

int f(x * y);
