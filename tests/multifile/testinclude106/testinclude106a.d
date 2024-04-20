module testinclude106a;

import config;
import cppconvhelpers;

int f()
{
    import testinclude106;

    return mixin(DATA1);
}

int g()
{
    static if (!defined!"DEF" && defined!"DEF2")
        import testinclude106c;
    static if (!defined!"DEF" && !defined!"DEF2" && defined!"DEF3")
        import testinclude106d;
    static if (!defined!"DEF" && !defined!"DEF2" && !defined!"DEF3")
        import testinclude106;
    static if (defined!"DEF")
        import testinclude106b;

    return data[0];
}

