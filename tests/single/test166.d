module test166;

import config;
import cppconvhelpers;

ushort  f(ushort  sum)
{
	return cast(ushort) ((~sum) + 1);
}
ushort  g(ushort  sum)
{
	return cast(ushort) (sum + 1);
}

