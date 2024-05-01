module testinclude108a;

import config;
import cppconvhelpers;
static if (defined!"DEF1")
    import testinclude108;

static if (defined!"DEF1")
{
__gshared auto f1 = int(X);
}

