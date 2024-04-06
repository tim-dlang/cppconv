void f();
void f3(int);

#ifdef DEF
#define F1 f();
#define F2 f()
#define F3(i) f3(i);
#define F4(i) f3(i)
#else
#define F1
#define F2
#define F3(i)
#define F4(i)
#endif

void g1a()
{
	F1
}
int g1b()
{
	int i;
	F1
	return i;
}
void g2a()
{
	F2;
}
int g2b()
{
	int i;
	F2;
	return i;
}
void g3a(int i)
{
	F3(i)
}
int g3b()
{
	int i;
	F3(i)
	return i;
}
void g4a(int i)
{
	F4(i);
}
int g4b()
{
	int i;
	F4(i);
	return i;
}

#define L(x) do {x} while(0);
void g5()
{
	L();
	L(f(););
}
