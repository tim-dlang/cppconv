typedef unsigned size_t;
#ifdef DEF
extern int snprintf (char *__s, size_t __maxlen,
		     const char *__format, ...);
#define p_snprintf(b, c, ...) snprintf(b, c, __VA_ARGS__)
#else
extern int p_snprintf (char *__s, size_t __maxlen,
		     const char *__format, ...);
#endif

void f(int value)
{
	char str_value[32];
	p_snprintf(str_value, sizeof(str_value), "%d", value);
}
