#ifdef DEF
typedef int id; // => cast
#else
void id(int); // => func call
#endif

int x;

auto f()
{
	return (id)(x);
}
