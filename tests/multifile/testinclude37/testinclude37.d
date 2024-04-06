module testinclude37;

import config;
import cppconvhelpers;

static if (defined!"DEF")
{
}
static if (!defined!"DEF" && defined!"DEF2")
{
}
static if (!defined!"DEF" && !defined!"DEF2")
{
struct S
{
}
}

