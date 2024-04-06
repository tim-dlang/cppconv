module testconflict_cf_f_4;

import config;
import cppconvhelpers;


size_t f(int slash)
{
	return cast( size_t ) ( slash + 1 );
}

