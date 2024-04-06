module testdefines5;

import config;
import cppconvhelpers;

/+ #define X "line1" \
	"line2" \
	"line3" \
	"line4" +/
enum X = "line1" ~
    	"line2" ~
    	"line3" ~
    	"line4";
__gshared const(char)* str = X;

