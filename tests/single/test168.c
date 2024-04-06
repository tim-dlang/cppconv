int f1(const char *p)
{
	for(;;)
	{
		switch ( * p )
		{
			case '\0' :
			return 1;
			default :
			break;
		}
		++ p;
	}
}
int f2(const char *p)
{
	while(1)
	{
		switch ( * p )
		{
			case '\0' :
			return 1;
			default :
			break;
		}
		++ p;
	}
}
void f3(const char *p)
{
	for(;;)
	{
		if ( * p == '\0' )
			break;
		++ p;
	}
}
