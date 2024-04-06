typedef struct
{
	enum {A=2, B, C} x;
} S;

void f(S *s)
{
	s->x = A;
}

int g(S *s)
{
	switch(s->x)
	{
		case A:
		return 42;
		case B:
		return 43;
		case C:
		return 44;
	}
	return -1;
}
