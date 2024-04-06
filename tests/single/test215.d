module test215;

import config;
import cppconvhelpers;

void f(T)(T t)
{
}

alias X = int;

int main()
{
	f!(X)(5);
	return 0;
}

