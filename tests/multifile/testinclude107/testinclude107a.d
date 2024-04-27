module testinclude107a;

import config;
import cppconvhelpers;
import testinclude107c;
static if (defined!"DEF")
    import testinclude107;

void f1(const(X)* x, const(Identity!(mixin((!defined!"DEF")?q{const(uint)}:q{const(S)})))* s)
{
}

