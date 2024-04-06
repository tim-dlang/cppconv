module testinclude76a;

import config;
import cppconvhelpers;

extern(D) static __gshared int proxyPort = 0;

int f1()
{
	return proxyPort;
}

