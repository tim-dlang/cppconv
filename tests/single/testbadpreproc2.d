module testbadpreproc2;

import config;
import cppconvhelpers;

/+ #define X 4+ +/
__gshared int test = /+ X +/4+ 5;

