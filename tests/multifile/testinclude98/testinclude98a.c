#include "testinclude98b.h"

#define	major_freebsd(x)	((Int32)(((x) & 0x0000ff00) >> 8))

int i = major_freebsd(0x0101);

#define D X + X

void g()
{
    int y = D;
}
