#if (defined(__amd64__) || defined(__amd64) || defined(__x86_64__) || defined(__x86_64) || \
     defined(i386) || defined(__i386) || defined(__i386__) || defined(__i486__)  || \
     defined(__i586__) || defined(__i686__) || defined(_M_IX86) || defined(__X86__) || \
     defined(_X86_) || defined(__THW_INTEL__) || defined(__I86__) || defined(__INTEL__) || \
     defined(__386) || defined(_M_X64) || defined(_M_AMD64))
#define SHA1DC_ON_INTEL_LIKE_PROCESSOR
#endif

#ifdef SHA1DC_ON_INTEL_LIKE_PROCESSOR
int x;
#endif
