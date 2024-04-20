module testinclude102c;

import config;
import cppconvhelpers;

struct Functions
{
    void function() fp;
}
/+ static void g(void); +/

void g()
{
}

__gshared const(Functions) functions = const(Functions)(&g);

