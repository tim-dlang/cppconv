module testppif12;

import config;
import cppconvhelpers;

/+ #ifdef DEF
#define A 1
#endif
#ifdef DEF2
#define B 1
#endif +/

static if ((configValue!"A" && 1 >= 1 && defined!"A" && defined!"DEF2") || (configValue!"A" && configValue!"B" >= 1 && defined!"A" && defined!"B" && !defined!"DEF" && !defined!"DEF2") || (defined!"DEF" && (defined!"DEF2" || (1 && configValue!"B" >= 1 && defined!"B"))))
{
void f();
}

