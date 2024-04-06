module test154;

import config;
import cppconvhelpers;

int f(int dict_size)
{
	if (dict_size < (1 << 12) || dict_size > (1 << 27)) {
		return 1;
	}
	return 2;
}

