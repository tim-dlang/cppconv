module testinclude102a;

import config;
import cppconvhelpers;

void f()
{
    import testinclude102b;
    import testinclude102d;

    g();
    wrap_g();
}

