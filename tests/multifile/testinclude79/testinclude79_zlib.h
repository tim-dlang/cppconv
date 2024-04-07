
#ifdef Z_LARGE64
   int gzopen64(void);
#endif

#if !defined(ZLIB_INTERNAL) && defined(Z_WANT64)
#  define gzopen gzopen64
#  ifndef Z_LARGE64
   int gzopen64(void);
#  endif
#else
   int gzopen(void);
#endif
