#define GIT_REFS_DIR "refs/"
#define GIT_REFS_HEADS_DIR GIT_REFS_DIR "heads/"

#define DOT_GIT ".git"
#define GIT_DIR DOT_GIT "/"

void f(const char *s);

void g()
{
	const char *fmt;
    fmt = "ref: " GIT_REFS_HEADS_DIR "%s\n";

	f("/" GIT_DIR);

    f("1");
    f("2");
    f("3" "4");
}
