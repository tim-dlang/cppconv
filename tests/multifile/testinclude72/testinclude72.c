unsigned char *f()
{
#ifdef DEF
	static const unsigned char data[5] = {11, 12, 13, 14, 15};
#else
	#include "testinclude72.h"
#endif
	return data;
}
