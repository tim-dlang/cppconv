struct S
{
	const char *name;
	void (*f)(void);
};

void f1(void);
void f2(void);

#define M(x) {#x, x}

const struct S funcs[] = {M(f1), M(f2)};
