extern int printf ( const char * format, ... );
int main()
{
	printf("test %s\n", "123");
	printf("test %s\n", 1 ? "456" : "789");
	return 0;
}
