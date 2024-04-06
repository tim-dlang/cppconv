module testinclude49;

import config;
import cppconvhelpers;

static if (!defined!"DEF" && defined!"DEF2")
{
/+ #define X 2 +/
enum X = 2;
}
static if (defined!"DEF")
{
/+ #define X 1 +/
enum X = 1;
}
static if (!defined!"DEF" && defined!"DEF2")
{
}
static if (!defined!"DEF" && !defined!"DEF2")
{
/+ #define X 3 +/
enum X = 3;
}

__gshared int x = mixin((defined!"DEF") ? q{
        X
    } : ((!defined!"DEF" && defined!"DEF2")) ? q{
        X
    } : q{
        X
    });

