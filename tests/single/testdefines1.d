module testdefines1;

import config;
import cppconvhelpers;

static if (defined!"DEF1")
{
/+ #define X 1 +/
enum X = 1;
__gshared int x1;
}
static if (!defined!"DEF1" && defined!"DEF2")
{
/+ #define X 2 +/
enum X = 2;
__gshared int x2;
}
static if (!defined!"DEF1" && !defined!"DEF2" && defined!"DEF3")
{
/+ #define X 3 +/
enum X = 3;
__gshared int x3;
}
static if (!defined!"DEF1" && !defined!"DEF2" && !defined!"DEF3")
{
/+ #define X -1 +/
enum X = -1;
__gshared int x4;
}

__gshared int test = mixin((defined!"DEF1") ? q{
        X
    } : ((!defined!"DEF1" && defined!"DEF2")) ? q{
        X
    } : ((!defined!"DEF1" && !defined!"DEF2" && defined!"DEF3")) ? q{
        X
    } : q{
        X
    });

