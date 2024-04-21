#ifdef DEF1
#define PRIX64 "llX"
#else
#define PRIX64 __PRI64_PREFIX "X"
#endif

#ifdef DEF2
#  define __PRI64_PREFIX	"l"
#else
#  define __PRI64_PREFIX	"ll"
#endif

typedef unsigned long long uint64_t;

void printf(const char *fmt, ...);

void f(uint64_t value)
{
    printf("(0x%016" PRIX64 ")", value);
}
