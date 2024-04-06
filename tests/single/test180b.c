#if defined(__BORLANDC__) || (defined(_MSC_VER) &&  _MSC_VER <= 1300)
# define	ARCHIVE_LITERAL_LL(x)	x##i64
# define	ARCHIVE_LITERAL_ULL(x)	x##ui64
#else
# define	ARCHIVE_LITERAL_LL(x)	x##ll
# define	ARCHIVE_LITERAL_ULL(x)	x##ull
#endif

#define X1 ARCHIVE_LITERAL_LL(42)
int i1 = X1;
#define X2 ARCHIVE_LITERAL_ULL(42)
int i2 = X2;
#define X3 ARCHIVE_LITERAL_LL(-42)
int i3 = X3;
#define X4 ARCHIVE_LITERAL_ULL(-42)
int i4 = X4;
