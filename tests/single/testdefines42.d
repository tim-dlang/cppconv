module testdefines42;

import config;
import cppconvhelpers;

/+ extern "C"
{
typedef struct FILE FILE;
extern FILE *stdout;
extern int fprintf(FILE *file, const char * format, ...);
}
#define printf2(...) fprintf (stdout, __VA_ARGS__)
#define printf3(format, ...) fprintf (stdout, format "\n" __VA_OPT__(,) __VA_ARGS__)
#define printf4(format, ...) fprintf (stdout, "%s" format "\n", "prefix" __VA_OPT__(,) __VA_ARGS__)

int main()
{
	printf2("\n");
	printf2("test\n");
	printf2("test %d x\n", 42);
	printf2("test %d %d x\n", 42, 43);
	printf3("");
	printf3("test");
	printf3("test %d x", 42);
	printf3("test %d %d x", 42, 43);
	printf4("");
	printf4("test");
	printf4("test %d x", 42);
	printf4("test %d %d x", 42, 43);
	return 0;
} +/

