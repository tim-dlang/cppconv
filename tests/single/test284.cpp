void g();
void h();
void f(int x)
{
#ifdef DEF
	if (x)
		g();
	else
#endif
		h();
}
