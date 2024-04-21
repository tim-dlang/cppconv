module testdefines70;

import config;
import cppconvhelpers;

static if (defined!"DEF1")
{
/+ #define PRIX64 "llX" +/
enum PRIX64 = "llX";
}
static if (!defined!"DEF1")
{
/+ #define PRIX64 __PRI64_PREFIX "X" +/
}

static if (defined!"DEF2")
{
/+ #  define __PRI64_PREFIX	"l" +/
enum __PRI64_PREFIX =	"l";
}
static if (!defined!"DEF2")
{
/+ #  define __PRI64_PREFIX	"ll" +/
enum __PRI64_PREFIX =	"ll";
}

alias uint64_t = ulong;

void printf(const(char)* fmt, ...);

void f(uint64_t value)
{
    printf("(0x%016" ~ mixin((defined!"DEF1") ? q{
            PRIX64
        } : ((!defined!"DEF1" && defined!"DEF2")) ? q{
        __PRI64_PREFIX
        } : q{
        __PRI64_PREFIX
        })~ mixin((!defined!"DEF1") ? q{
                "X"
            } : q{
        ""
            }) ~ ")", value);
}

