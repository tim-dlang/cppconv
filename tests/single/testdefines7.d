module testdefines7;

import config;
import cppconvhelpers;

/+ #define A 1 +/
/+ #define B A +/
enum B = A;
/+ #define A 2 +/
enum A = 2;
__gshared int test = B;

