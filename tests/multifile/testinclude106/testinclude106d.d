/* empty */
module testinclude106d;

import config;
import cppconvhelpers;

static if (!defined!"DEF" && !defined!"DEF2" && defined!"DEF3")
{
__gshared ubyte[16]  data = mixin(buildStaticArray!(q{ubyte}, 16, q{cast(ubyte) (201), cast(ubyte) (202), cast(ubyte) (203)}));
}

