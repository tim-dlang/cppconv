#define A 1
#define f(x,y,z) A
int x = f
(
a,
#undef A
#define A 2
b,
c
);
