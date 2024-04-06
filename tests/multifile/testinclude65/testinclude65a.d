
module testinclude65a;

import config;
import cppconvhelpers;

/+ extern char *p_realpath(const char *, char *); +/

void f(const(char)* url)
{
    import testinclude65b;

	p_realpath(url, null);
}

