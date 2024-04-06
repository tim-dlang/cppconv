#define TEST i = i * 2; i = i + 3;

void f()
{
	int i = 2;
	TEST
	TEST
	i = 5;
	TEST
}
