module test110;

import config;
import cppconvhelpers;

int f()
{
	return 5;
}

int g(int function() f__1)
{
	return f__1();
}

int main()
{
	return g(&f);
}

