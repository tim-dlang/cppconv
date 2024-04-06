struct Size
{
};

class C
{
public:
	void resize(int w, int h);
	void resize(const Size &size);
};

void f()
{
	C c;
	c.resize(100, 200);
}
