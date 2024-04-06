
module testppif8;

import config;
import cppconvhelpers;

/+ #if (__WORDSIZE == 64 && !defined(_LIBC_LIMITS_H_) && (__GNUC__ < 2 || !defined(__GNUC__)))
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
#endif +/

static if ((configValue!"ULONG_MAX" == 4294967295 && defined!"ULONG_MAX" && (configValue!"__WORDSIZE" != 64 || !defined!"__WORDSIZE")) || (configValue!"__WORDSIZE" == 64 && defined!"__WORDSIZE" && ((configValue!"ULONG_MAX" == -1 && defined!"ULONG_MAX") || (!defined!"_LIBC_LIMITS_H_" && (configValue!"__GNUC__" < 2 || !defined!"__GNUC__")))) || (!defined!"_LIBC_LIMITS_H_" && (configValue!"__GNUC__" < 2 || !defined!"__GNUC__") && (configValue!"__WORDSIZE" != 64 || !defined!"__WORDSIZE")))
{
__gshared int a;
}
static if ((configValue!"ULONG_MAX" != 4294967295 || !defined!"ULONG_MAX" || (configValue!"__WORDSIZE" == 64 && defined!"__WORDSIZE")) && (configValue!"__WORDSIZE" != 64 || !defined!"__WORDSIZE" || ((configValue!"ULONG_MAX" != -1 || !defined!"ULONG_MAX") && (defined!"_LIBC_LIMITS_H_" || (configValue!"__GNUC__" >= 2 && defined!"__GNUC__")))) && (defined!"_LIBC_LIMITS_H_" || (configValue!"__GNUC__" >= 2 && defined!"__GNUC__") || (configValue!"__WORDSIZE" == 64 && defined!"__WORDSIZE")))
{
__gshared int b;
}

