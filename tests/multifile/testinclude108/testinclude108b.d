module testinclude108b;

import config;
import cppconvhelpers;
static if (!defined!"DEF1")
    import testinclude108;

static if (!defined!"DEF1")
{
static if (defined!"DEF2")
{
int f2(X);
}
static if (!defined!"DEF2")
{
__gshared auto f2 = int(X);
}
}

