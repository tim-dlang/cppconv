int i;
double d;
void f()
{
	double y =
	#ifdef DEF
	i
	#else
	d
	#endif
	;
}
