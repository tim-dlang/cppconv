module test174;

import config;
import cppconvhelpers;

__gshared int[2] n = [0, 0];
struct X
{
	int* next;
}
struct S
{
	X x;
}
__gshared S s = S(X(n.ptr));
 __gshared S* state = &s;
int main()
{
	return */*(*/state.x.next/*)*/++;
}

