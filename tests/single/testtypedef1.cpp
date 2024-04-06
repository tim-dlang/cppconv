typedef struct git_oidarray {
	char *ids;
	int count;
} git_oidarray;

void f(git_oidarray x);

git_oidarray a;
