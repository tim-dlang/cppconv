module testconflict_cu_f_8;

import config;
import cppconvhelpers;

void g(int);
void f()
{
	g(cast(int) (cast(size_t)-1));
}

