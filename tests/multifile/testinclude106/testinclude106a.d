module testinclude106a;

import config;
import cppconvhelpers;

int f()
{
    import testinclude106;

    return mixin(DATA1);
}

