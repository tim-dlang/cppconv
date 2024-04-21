const char *s1 = "prefix"
#ifdef DEF1
"_suffix1"
#elif defined(DEF2)
"_suffix2"
#endif
;
const char *s2 =
#ifdef DEF1
"prefix1_"
#elif defined(DEF2)
"prefix2_"
#endif
"suffix"
;
const char *s3 = "pre" "fix"
#ifdef DEF1
"_suffix1"
#elif defined(DEF2)
"_suffix2"
#endif
;
const char *s4 =
#ifdef DEF1
"prefix1_"
#elif defined(DEF2)
"prefix2_"
#endif
"suf" "fix"
;
const char *s5 = "prefix_"
#ifdef DEF1
"middle1"
#elif defined(DEF2)
"middle2"
#endif
"_suffix"
;
