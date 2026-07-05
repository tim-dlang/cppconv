#undef IN_A
#include "testinclude111.h"

const char *a = STRINGIFY(B);

void g()
{
    const int i_b = i;
    const char *str_b = str;
}
