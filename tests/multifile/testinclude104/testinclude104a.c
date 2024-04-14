#include "testinclude104b.h"

int f(S *s)
{
    switch (s->e)
    {
    case A:
        return 1;
    case B:
        return 2;
#ifdef DEF
    case C:
        return 3;
#endif
    case D:
        return 4;
    default:
        return -1;
    }
}
