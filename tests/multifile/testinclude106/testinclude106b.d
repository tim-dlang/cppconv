module testinclude106b;

import config;
import cppconvhelpers;

static if (defined!"DEF")
{
__gshared ubyte[16]  data = mixin(buildStaticArray!(q{ubyte}, 16, q{cast(ubyte) (1), cast(ubyte) (2), cast(ubyte) (3)}));
}

