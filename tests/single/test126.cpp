struct S
{
	S *s;
};
S *f(unsigned)
{
	return 0;
}
int main()
{
	S *db = f(sizeof(*db));
	S s = {&s};
	return 0;
}
