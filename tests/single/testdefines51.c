#ifdef DEF
void write_impl(const char *s);
#define write write_impl
#else
void write(const char *s);
#endif

struct S
{
	void (*write)(const char *s);
};

void f1(struct S *x)
{
	x->write = write;
}

void f2(struct S *x, const char *str)
{
	x->write(str);
}
