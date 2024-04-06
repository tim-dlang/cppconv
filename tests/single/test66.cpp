struct S
{
	int id;
};

int f()
{
	S s;
	return s.id;
}
int g(S *s)
{
	return s->id;
}
