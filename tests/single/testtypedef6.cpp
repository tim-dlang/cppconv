typedef
#ifdef DEF
int
#else
float
#endif
X;

typedef X Y;

typedef Y Z;

void test(Z){}
