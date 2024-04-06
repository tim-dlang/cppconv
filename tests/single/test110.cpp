int f()
{
	return 5;
}

int g(int (*f)(void))
{
	return f();
}

int main()
{
	return g(f);
}
