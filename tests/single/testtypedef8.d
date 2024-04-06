module testtypedef8;

import config;
import cppconvhelpers;

alias func = int function(int, ...);

int g(int, ...);

__gshared func f = &g;

