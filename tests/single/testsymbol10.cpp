class C
{
public:
	void f();
	int f(int, int);
	void f(const char *);
	void f(int[2]);
	void f(double);
};

// comment1a
void C::f(const char *s)
{
	// comment1b
}

// comment2a
void C::f(double d)
{
	// comment2b
}

// comment3a
void C::f()
{
	// comment3b
}

// comment4a
void C::f(int arr[2])
{
	// comment4b
}

// comment5a
int C::f(int x, int y)
{
	// comment5b
	return x + y;
}
