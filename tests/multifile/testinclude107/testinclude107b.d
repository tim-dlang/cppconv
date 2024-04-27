module testinclude107b;

import config;
import cppconvhelpers;
static if (defined!"DEF" && defined!"DEF2")
    import testinclude107;
static if (defined!"DEF2")
    import testinclude107c;

/+ #ifdef DEF2 +/

static if (defined!"DEF2")
{
void f2(const(X)* x, const(Identity!(mixin((defined!"DEF")?q{const(S)}:q{const(uint)})))* s)
{
}
}

/+ #endif +/

