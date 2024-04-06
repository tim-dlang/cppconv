typedef int (*func)(int, ...);

int g(int, ...);

func f = &g;
