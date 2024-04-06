
#include "testinclude65.h"

extern char *p_realpath(const char *, char *);

static void f(const char *url)
{
	p_realpath(url, 0);
}
