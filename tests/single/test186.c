
#ifdef _WIN32
#   ifdef BZ_EXPORT
#   define BZ_API(func) func
#   define BZ_EXTERN extern
#   else
   /* import windows dll dynamically */
#   define BZ_API(func) (* func)
#   define BZ_EXTERN
#   endif
#else
#   define BZ_API(func) func
#   define BZ_EXTERN extern
#endif

int BZ_API(BZ2_bzCompressInit)
                    (int        workFactor )
{
	return 0;
}

int (BZ2_bzCompressInit2)
                    ( )
{
	return 0;
}
