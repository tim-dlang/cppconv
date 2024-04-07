module test180b;

import config;
import cppconvhelpers;

/+ #if defined(__BORLANDC__) || (defined(_MSC_VER) &&  _MSC_VER <= 1300)
# define	ARCHIVE_LITERAL_LL(x)	x##i64
# define	ARCHIVE_LITERAL_ULL(x)	x##ui64
#else
# define	ARCHIVE_LITERAL_LL(x)	x##ll
# define	ARCHIVE_LITERAL_ULL(x)	x##ull
#endif +/

/+ #define X1 ARCHIVE_LITERAL_LL(42) +/
enum X1 = mixin(((defined!"__BORLANDC__" || (configValue!"_MSC_VER" < 1301 && defined!"_MSC_VER"))) ? q{
             /+ ARCHIVE_LITERAL_LL(42) +/42L
         } : q{
            42L
         });
__gshared int i1 = X1;
/+ #define X2 ARCHIVE_LITERAL_ULL(42) +/
enum X2 = mixin(((defined!"__BORLANDC__" || (configValue!"_MSC_VER" < 1301 && defined!"_MSC_VER"))) ? q{
             /+ ARCHIVE_LITERAL_ULL(42) +/42uL
         } : q{
            42uL
         });
__gshared int i2 = X2;
/+ #define X3 ARCHIVE_LITERAL_LL(-42) +/
enum X3 = mixin(((defined!"__BORLANDC__" || (configValue!"_MSC_VER" < 1301 && defined!"_MSC_VER"))) ? q{
             /+ ARCHIVE_LITERAL_LL(-42) +/-42L
         } : q{
            cast(int) (-42L)
         });
__gshared int i3 = X3;
/+ #define X4 ARCHIVE_LITERAL_ULL(-42) +/
enum X4 = mixin(((defined!"__BORLANDC__" || (configValue!"_MSC_VER" < 1301 && defined!"_MSC_VER"))) ? q{
             /+ ARCHIVE_LITERAL_ULL(-42) +/-42uL
         } : q{
            cast(int) (-42uL)
         });
__gshared int i4 = X4;

