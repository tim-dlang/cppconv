module testbadpreproc1;

import config;
import cppconvhelpers;

/+ #define plus(x, y) x+y +/
__gshared int test = 5 * /+ plus(2,3) +/2+3;

