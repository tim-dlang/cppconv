void v(const char *t, ...);
void f()
{
	char buf[20];
	v("%s", buf);
}
