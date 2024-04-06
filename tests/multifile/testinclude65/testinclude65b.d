
module testinclude65b;

import config;
import cppconvhelpers;

char* p_realpath(const(char)* pathname, char* resolved)
{
	return cast(char*) (pathname);
}

