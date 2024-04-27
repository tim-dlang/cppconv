module testinclude107c;

import config;
import cppconvhelpers;
static if (defined!"DEF")
    import testinclude107;

struct X
{
    Identity!(mixin((!defined!"DEF")?q{uint}:q{S}))* s;
}
