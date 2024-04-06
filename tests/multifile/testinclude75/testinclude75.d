
module testinclude75;

import config;
import cppconvhelpers;

/+ #define F1          SORT_MAKE_STR(f1) +/
alias F1 =          /+ SORT_MAKE_STR(f1) +/x_f1;

int x_f1/+ F1 +/(int i)
{
	return i + 1;
}
int x_f2/+ F2 +/(int i)
{
	return i + 2;
}
/+ #define SORT_NAME x +/
int g1(int i)
{
	return F1(i*2);
}
int g2(int i)
{
	return x_f2(i*2);
}

