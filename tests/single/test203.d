module test203;

import config;
import cppconvhelpers;

void g(int);
int h();

void f()
{
	for(int i=0; i<10; i++)
		g(i);
	for(int i=0; i<10; i++)
	{
		g(i);
	}
	if(int i = 30)
		g(i);
	while(int i = h())
		g(i);
	switch(int i = h())
	{
		case 0:
			break;
		default:
			g(i);
	}
}

