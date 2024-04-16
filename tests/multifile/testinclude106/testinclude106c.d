module testinclude106c;

import config;
import cppconvhelpers;

static if (!defined!"DEF" && defined!"DEF2")
{
__gshared ubyte[16]  data = mixin(buildStaticArray!(q{ubyte}, 16, q{cast(ubyte) (101), cast(ubyte) (102), cast(ubyte) (103)}));
}

