module testconflict_cf_f_5;

import config;
import cppconvhelpers;


size_t f(long min_length)
{
	return cast( size_t ) ( cast( int ) min_length );
}

