class P
{
public:
	virtual void f();
};
class C: public P
{
public:
	void f() final;
};
void f()
{
	int final;
	C *c = new C;
	c->f();
}
