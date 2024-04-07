#ifdef DEF
void write_impl(const char *s);
void write_impl_debug(const char *s, const char *file, int line);
#define write write_impl
#define write2(s) write_impl(s)
#define write3(s) write_impl_debug(s, __FILE__, __LINE__)
#define write4(s) write_impl(s);
#else
void write(const char *s);
void write2(const char *s);
void write3(const char *s);
void write4(const char *s);
#endif

void f(void)
{
	write("test");
	write2("test");
	write3("test");
	write4("test");
}
void g(const char *str)
{
	write(str);
	write2(str);
	write3(str);
	write4(str);
}
