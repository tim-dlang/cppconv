module testdefines59;

import config;
import cppconvhelpers;

/+ #define f(a, b, c) a ## b ## c +/

static if (defined!"DEF")
{
__gshared const(int) test_a = 100;
__gshared const(int) test_b = 200;
}
static if (!defined!"DEF")
{
/+ #define test_a 1 +/
enum test_a = 1;
/+ #define test_b 2 +/
enum test_b = 2;
}

__gshared int i = /+ f(test_, a + test_, b) +/ mixin((!defined!"DEF") ? q{
        test_a
    } : q{
        test_a
    })+ mixin((!defined!"DEF") ? q{
            test_b
        } : q{
        test_b
        });

