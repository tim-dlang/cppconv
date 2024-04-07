#include "testinclude101a.h"
#ifdef DEF
#include "testinclude101b.h"
#endif
#define X Y

extern X i;

void g()
{
    f();
}
