module test168;

import config;
import cppconvhelpers;

int f1(const(char)* p)
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
	}assert(false);

}
int f2(const(char)* p)
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
	}assert(false);

}
void f3(const(char)* p)
{
	for(;;)
	{
		if ( * p == '\0' )
			break;
		++ p;
	}
}

