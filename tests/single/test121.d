module test121;

import config;
import cppconvhelpers;

int printf ( const(char)*  format, ... );
int main()
{
	printf("test %s\n", "123".ptr);
	printf("test %s\n", 1 ? "456".ptr : "789".ptr);
	return 0;
}

