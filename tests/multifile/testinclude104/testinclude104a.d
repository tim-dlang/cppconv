module testinclude104a;

import config;
import cppconvhelpers;
import testinclude104b;

int f(S* s)
{
    import testinclude104b_enum;

    switch (s.e)
    {
    case E.A:
        return 1;
    case E.B:
        return 2;
    static if (defined!"DEF")
    {
        case E.C:
            return 3;
    }
    case E.D:
        return 4;
    default:
        return -1;
    }
}

