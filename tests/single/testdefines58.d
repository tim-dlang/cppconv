module testdefines58;

import config;
import cppconvhelpers;

/+ #define X a
#define Y b +/
/+ #define XY(x) x * 5 +/
template XY(params...) if (params.length == 1)
{
    enum x = params[0];
    enum XY = x * 5;
}
/+ #define Z X ## Y (2) +/
enum Z = XY!(2);/+ X ## Y (2) +/
__gshared int i1 = Z;

