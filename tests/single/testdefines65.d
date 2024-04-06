module testdefines65;

import config;
import cppconvhelpers;

/+ #define TEST i = i * 2; i = i + 3; +/
enum TEST = q{i = i * 2; i = i + 3;};

void f()
{
	int i = 2;
	mixin(TEST);
	mixin(TEST);
	i = 5;
	mixin(TEST);
}

