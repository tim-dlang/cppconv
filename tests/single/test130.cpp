#define va_start(v,l)	__builtin_va_start(v,l)
#define va_end(v)	__builtin_va_end(v)
#define va_arg(v,l)	__builtin_va_arg(v,l)
#define va_copy(d,s)	__builtin_va_copy(d,s)
#define va_list __builtin_va_list
extern "C"
{
	extern int printf ( const char * format, ... );
	typedef unsigned long size_t;
	extern size_t strlen(const char*);
}
int git_buf_join_n(int nbuf, ...)
{
	va_list ap;
	int i;

	va_start(ap, nbuf);
	for (i = 0; i < nbuf; ++i) {
		const char* segment;
		size_t segment_len;

		segment = va_arg(ap, const char *);

		printf(" i=%d\n", i);
		printf("  segment pointer %p\n", segment);
		printf("  segment \"%s\"\n", segment);
		if (!segment)
			continue;

		segment_len = strlen(segment);
		printf("  segment_len %zd\n", segment_len);
	}
	va_end(ap);

	va_start(ap, nbuf);
	for (i = 0; i < nbuf; ++i) {
		const char* segment;
		size_t segment_len;

		segment = va_arg(ap, const char *);
		printf(" i=%d\n", i);
		printf("  segment pointer %p\n", segment);
		printf("  segment \"%s\"\n", segment);
		if (!segment)
			continue;

		segment_len = strlen(segment);
		printf("  segment_len %zd\n", segment_len);
	}
	va_end(ap);

	return 0;
}

int main()
{
	git_buf_join_n(4, "test", "asdf", "abcdef", "xyz");
	return 0;
}

