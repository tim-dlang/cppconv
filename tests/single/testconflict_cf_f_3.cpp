struct id{
	id(int){}
}; // => cast
#ifndef DEF
void id(int); // => func call
#endif

int x;

void f()
{
	(id)(x);
}
