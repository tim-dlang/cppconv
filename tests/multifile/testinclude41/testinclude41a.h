void git__memzero();

#ifdef GIT_WIN32
void git__timer();
#else
#include "testinclude41b.h"
void f()
{
	gettimeofday();
}
#endif
