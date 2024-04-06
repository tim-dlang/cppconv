class C
{
public:
	C(unsigned int);
	C(unsigned long);
	C(unsigned short);
	C(int) : a(1), b(2), c(3) { }
	C(long) : a(1), b(2), c(3)
	{ }
	C(char) : a(1), b(2), c(3) { f(); }
	C(short) : a(1), b(2), c(3)
	{ f(); }

	int a, b, c;

	void f() {}
};

C::C(unsigned int) :
    a(1),
    b(2)
{

}
C::C(unsigned long)
    : a(1), b(2)
{
	void f();
}
C::C(unsigned short)
    : a(1)
    , b(2)
    , c(3)
{
}
