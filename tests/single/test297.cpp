#  define Q_UINT64_C(c) ((unsigned long long)(c ## ULL))

int a = Q_UINT64_C(1);
int b = Q_UINT64_C ( 2 ) ;
int c = Q_UINT64_C/*x*/(/*y*/3/*z*/)/*w*/;
#if 0
int d = Q_UINT64_C(4);
#endif
