
module test364;

import config;
import cppconvhelpers;

/+ #ifdef ALWAYS_PREDEFINED_IN_TEST
#unknown CPPCONV_OS
#alias CPPCONV_OS_WIN CPPCONV_OS == 2
#endif

#undef _WIN32
#ifdef CPPCONV_OS_WIN
#define _WIN32
#endif +/

int f(int p)
{
/+ #if !defined(_WIN32) +/
    static if (!versionIsSet!("Windows"))
    {
        if (p)
    /+ #endif
    #if 1 +/
        {
            return 1;
        }
    /+ #endif
    #if !defined(_WIN32) +/
        else
    /+ #endif
    #if !defined(_WIN32) +/
        {
            return 2;
        }
    }
    else
    {
    {return 1;}
    }
/+ #endif +/
}

int f2()
{
    static if (!versionIsSet!("DEF1"))
    {
        return 1;
    }
    else
    {
        return 2;
    }
}

