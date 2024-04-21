module testdefines69;

import config;
import cppconvhelpers;

struct S
{
    /+ S() = default; +/
    this(long ){}
}

static if (defined!"DEF")
{
/+ #define T int +/
alias T = int;
}
static if (!defined!"DEF" && defined!"DEF2")
{
/+ #define T unsigned +/
alias T = uint;
}
static if (!defined!"DEF" && !defined!"DEF2" && defined!"DEF3")
{
/+ #define T unsigned long long +/
}
static if (!defined!"DEF" && !defined!"DEF2" && !defined!"DEF3")
{
/+ #define T S +/
alias T = S;
}

__gshared Identity!(mixin(((defined!"DEF" || defined!"DEF2" || !defined!"DEF3"))?q{T}:q{ulong})) x;
__gshared const(Identity!(mixin(((defined!"DEF" || defined!"DEF2" || !defined!"DEF3"))?q{const(T)}:q{const(ulong)}))) x2 = cast(const(Identity!(mixin((defined!"DEF")?q{const(int)}:((!defined!"DEF" && defined!"DEF2"))?q{const(uint)}:((!defined!"DEF" && !defined!"DEF2" && defined!"DEF3"))?q{const(ulong)}:q{const(S)})))) (0);

void f(Identity!(mixin(((defined!"DEF" || defined!"DEF2" || !defined!"DEF3"))?q{T}:q{ulong})) y);
void f2(const(Identity!(mixin(((defined!"DEF" || defined!"DEF2" || !defined!"DEF3"))?q{const(T)}:q{const(ulong)}))) y);

struct S2(T2)
{
}

__gshared S2!(/+ T +/Identity!(mixin(((defined!"DEF" || defined!"DEF2" || !defined!"DEF3"))?q{T}:q{ulong}))) z;
__gshared S2!(const(Identity!(mixin(((defined!"DEF" || defined!"DEF2" || !defined!"DEF3"))?q{const(T)}:q{const(ulong)})))) z2;

