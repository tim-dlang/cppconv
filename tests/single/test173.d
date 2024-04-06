module test173;

import config;
import cppconvhelpers;

struct S
{
	int x;
}
/+ struct S data; +/
__gshared S data = S(5);

int main()
{
	return data.x;
}

