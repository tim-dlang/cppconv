module testinclude101;

import config;
import cppconvhelpers;
import testinclude101a;
static if (defined!"DEF")
    import testinclude101b;

/+ #ifdef DEF
#endif +/
/+ #define X Y +/
alias X = Identity!(mixin((!defined!"DEF")?q{testinclude101a.Y}:q{testinclude101b.Y}));

extern __gshared X i;

void g()
{
    f();
}

