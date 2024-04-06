module test108;

import config;
import cppconvhelpers;

static if (defined!"DEF")
{
/+ #define X "d" +/
enum X = "d";
}
static if (!defined!"DEF")
{
/+ #define X "ld" +/
enum X = "ld";
}

__gshared const(char)* format = "text %" ~ mixin((defined!"DEF") ? q{
        X
    } : q{
        X
    }) ~ " text";

