module testconflict_dt_f_1;

import config;
import cppconvhelpers;

void f(int* word, int mask)
{
	* word &= ~ mask;
}

