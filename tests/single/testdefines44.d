module testdefines44;

import config;
import cppconvhelpers;

static if (defined!"DEF")
{
int snprintf (char* __s, size_t __maxlen,
		     const(char)* __format, ...);
/+ #define p_snprintf(b, c, ...) snprintf(b, c, __VA_ARGS__) +/
}
static if (!defined!"DEF")
{
int p_snprintf (char* __s, size_t __maxlen,
		     const(char)* __format, ...);
}

void f(int value)
{
	char[32] str_value;
	(mixin((defined!"DEF") ? q{
        	/+ p_snprintf(str_value, sizeof(str_value), "%d", value) +/snprintf(str_value.ptr,cast(size_t) (( (str_value).length ) * char.sizeof),"%d",value)
    	} : q{
        p_snprintf(str_value.ptr,cast(size_t) (( (str_value).length ) * char.sizeof),"%d",value)
    	}));
}

