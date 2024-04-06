typedef unsigned long size_t;
void g(int);
void f()
{
	g((size_t)-1);
}
