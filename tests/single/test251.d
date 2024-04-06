module test251;

import config;
import cppconvhelpers;

static if (!defined!"WIN")
{

/+ #ifdef __cplusplus
extern "C" {
#endif +/

static if (defined!"__CORRECT_ISO_CPP_STRING_H_PROTO")
{
/+ extern "C++"
{ +/
char* strstr (char* __haystack, const(char)* __needle)/+
     __asm ("strstr")+/;
const(char)* strstr (const(char)* __haystack, const(char)* __needle)/+
     __asm ("strstr")+/;
/+ } +/
}
static if (!defined!"__CORRECT_ISO_CPP_STRING_H_PROTO")
{
char* strstr (const(char)* __haystack, const(char)* __needle);
}

/+ #ifdef __cplusplus
}
#endif +/

}
static if (defined!"WIN")
{

/+ #ifdef __cplusplus
extern "C" {
#endif +/

char* strstr(const(char)*, const(char)*);

/+ #ifdef __cplusplus
}
#endif +/

}

void f(char* progName)
{
   if ( (strstr ( progName, "unzip" ) != null) ||
        (strstr ( progName, "UNZIP" ) != null) )
   {}
}

