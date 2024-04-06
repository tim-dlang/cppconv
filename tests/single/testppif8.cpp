
#if (__WORDSIZE == 64 && !defined(_LIBC_LIMITS_H_) && (__GNUC__ < 2 || !defined(__GNUC__)))
#   define ULONG_MAX	18446744073709551615UL
#elif (__WORDSIZE != 64 && !defined(_LIBC_LIMITS_H_) && (__GNUC__ < 2 || !defined(__GNUC__)))
#   define ULONG_MAX	4294967295UL
#endif

#if __WORDSIZE == 64
#  define SIZE_MAX		(18446744073709551615UL)
#elif (__WORDSIZE != 64 && __WORDSIZE32_SIZE_ULONG)
#   define SIZE_MAX		(4294967295UL)
#elif (__WORDSIZE != 64 && !__WORDSIZE32_SIZE_ULONG)
#   define SIZE_MAX		(4294967295U)
#endif

#if (SIZE_MAX == ULONG_MAX)
int a;
#else
int b;
#endif
