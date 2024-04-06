module testdefines60;

import config;
import cppconvhelpers;

/+ #define CONCAT2(a, b) a ## b
#define CONCAT(a, b) CONCAT2(a, b)

#define A a
#define B 2 * A
#define C 4 * B +/

__gshared const(int) ax = 100;

__gshared int i = /+ CONCAT(C, x) +/4*2*ax;

