class A
{
public:
	void f();
	virtual void g();
	friend void h();
	void i() const;
	virtual void j() const;
	virtual void k(int i=5) = 0;
};

class B: public A
{
public:
	void g() override;
	virtual void j() const override;
	virtual void k(int i=5) override;
};
