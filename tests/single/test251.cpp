#ifndef WIN

#ifdef __cplusplus
extern "C" {
#endif

#ifdef __CORRECT_ISO_CPP_STRING_H_PROTO
extern "C++"
{
extern char *strstr (char *__haystack, const char *__needle)
     __asm ("strstr");
extern const char *strstr (const char *__haystack, const char *__needle)
     __asm ("strstr");
}
#else
extern char *strstr (const char *__haystack, const char *__needle);
#endif

#ifdef __cplusplus
}
#endif

#else

#ifdef __cplusplus
extern "C" {
#endif

char* strstr(const char*,const char*);

#ifdef __cplusplus
}
#endif

#endif

void f(char *progName)
{
   if ( (strstr ( progName, "unzip" ) != 0) ||
        (strstr ( progName, "UNZIP" ) != 0) )
   {}
}
