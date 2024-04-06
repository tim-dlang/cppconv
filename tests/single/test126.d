module test126;

import config;
import cppconvhelpers;

struct S
{
	S* s;
}
S* f(uint)
{
	return null;
}
int main()
{
	S* db ;
	db= f(cast(uint) ((*db). sizeof));
	S s ;
	s= S(&s);
	return 0;
}

