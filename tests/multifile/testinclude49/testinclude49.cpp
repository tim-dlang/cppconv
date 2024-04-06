#ifdef DEF
#define X 1
#elif defined(DEF2)
#include "testinclude49.h"
#else
#define X 3
#endif

int x = X;
