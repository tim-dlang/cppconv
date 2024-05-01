module testinclude108;

import config;
import cppconvhelpers;

static if (!defined!"DEF2")
{
__gshared const(int) X = 5;
}
static if (defined!"DEF2")
{
alias X = int;
}

