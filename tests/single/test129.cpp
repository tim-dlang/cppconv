int f(int i)
{
	for(int k=i; k < i+10; k++)
	{
	#ifndef DEF
		int i = k + 1000;
	#endif
		return i;
	}
	return -1;
}

int main()
{
	f(5);
	return 0;
}
