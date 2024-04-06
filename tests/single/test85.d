module test85;

import config;
import cppconvhelpers;

static if (defined!"DEF")
{
alias Point = int[2];
}
static if (!defined!"DEF")
{
struct Point
{
	int x;
	int y;
}
}

alias P = Point;

__gshared P point1 = mixin(((defined!"DEF") ? "[" : "Point(") ~ q{1, 2
}
 ~ ((defined!"DEF") ? "]" : ")"));
__gshared /+ P[0]  +/ auto points = mixin(buildStaticArray!(q{P}, q{ mixin(((defined!"DEF") ? "[" : "Point(") ~ q{1, 2
}
 ~ ((defined!"DEF") ? "]" : ")")), mixin(((defined!"DEF") ? "[" : "Point(") ~ q{3, 4
}
 ~ ((defined!"DEF") ? "]" : ")")), mixin(((defined!"DEF") ? "[" : "Point(") ~ q{5, 6
}
 ~ ((defined!"DEF") ? "]" : ")"))}));

