module testinclude76b;

import config;
import cppconvhelpers;

extern(D) static __gshared int proxyPort;

int f2()
{
	return proxyPort;
}

