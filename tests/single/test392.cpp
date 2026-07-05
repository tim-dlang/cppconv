#define IDENTITY(x) x

struct S
{
};

int s1 = sizeof(IDENTITY(int));
int s2 = sizeof(IDENTITY(S));
