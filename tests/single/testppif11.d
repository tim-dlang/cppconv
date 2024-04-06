module testppif11;

import config;
import cppconvhelpers;

/+ #ifdef DEF
#define LZO_ARCH_ARM_THUMB1 1
#endif
#ifdef DEF2
#define LZO_ARCH_ARM_THUMB2 1
#endif +/

static if ((configValue!"LZO_ARCH_ARM_THUMB1" && defined!"LZO_ARCH_ARM_THUMB1" && (defined!"DEF2" || (configValue!"LZO_ARCH_ARM_THUMB2" && defined!"LZO_ARCH_ARM_THUMB2"))) || (defined!"DEF" && (defined!"DEF2" || (configValue!"LZO_ARCH_ARM_THUMB2" && defined!"LZO_ARCH_ARM_THUMB2"))))
{
void f();
}

