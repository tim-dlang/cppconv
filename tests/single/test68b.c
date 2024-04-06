
void f1(char *s);
void f2(const char *s);
void f3(void *s);
void f4(const void *s);
void g()
{
	char s[2] = {'a', '\0'};
	f1(s);
	f2(s);
	f3(s);
	f4(s);
	const char s2[] = {'a', '\0'};
	//f1(s2);
	f2(s2);
	//f3(s2);
	f4(s2);
	void *s3 = s;
	f1(s3);
	f2(s3);
	f3(s3);
	f4(s3);
}
