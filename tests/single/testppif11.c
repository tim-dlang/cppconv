#ifdef DEF
#define LZO_ARCH_ARM_THUMB1 1
#endif
#ifdef DEF2
#define LZO_ARCH_ARM_THUMB2 1
#endif

#if (LZO_ARCH_ARM_THUMB1 && LZO_ARCH_ARM_THUMB2)
void f();
#endif
