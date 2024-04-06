module test63;

import config;
import cppconvhelpers;

void f(int* data)
{

}
void g()
{
	int[4] data;
	f(data.ptr);
	int* data2 = data.ptr;
	f(data2);
}

