module test107;

import config;
import cppconvhelpers;

void f(int/+[0]+/* data);
void g(int/+[5]+/* data);

struct git_oid;
void h(const(git_oid)*/+[0]+/* parents);

int main()
{
	int[10] data;
	f(data.ptr);
	g(data.ptr);
	const(git_oid)*[10] parents;
	h(parents.ptr);
	return 0;
}

