module testdefines9;

import config;
import cppconvhelpers;

static if (defined!"DEF")
{
/+ #define X 1 +/
enum X = 1;
}
static if (!defined!"DEF" && defined!"DEF2")
{
/+ #define X 2 +/
enum X = 2;
}
static if (!defined!"DEF" && !defined!"DEF2")
{
/+ #define X 3 +/
enum X = 3;
}

static if (defined!"DEF")
{
__gshared int test1 = X;
}
static if (!defined!"DEF")
{
__gshared int test2 = mixin((defined!"DEF2") ? q{
        X
    } : q{
        X
    });
}

