module testppif7;

import config;
import cppconvhelpers;

/+ #ifdef DEF
#define X (2)
#elif defined(DEF2)
#define X (1)
#endif



#ifndef DEF3
#define Y (2)
#elif defined(DEF4)
#define Y (1)
#endif +/


static if ((!configValue!"X" && !defined!"DEF" && !defined!"DEF2" && defined!"DEF3" && !defined!"DEF4" && !defined!"Y") || (configValue!"X" == 1 && !defined!"DEF" && defined!"DEF3" && defined!"DEF4" && defined!"X") || (configValue!"X" == 2 && !defined!"DEF2" && !defined!"DEF3" && defined!"X") || (configValue!"X"==configValue!"Y" && !defined!"DEF" && !defined!"DEF2" && defined!"DEF3" && !defined!"DEF4" && defined!"X" && defined!"Y") || (!configValue!"Y" && !defined!"DEF" && !defined!"DEF2" && defined!"DEF3" && !defined!"DEF4" && !defined!"X") || (configValue!"Y" == 1 && !defined!"DEF" && defined!"DEF2" && defined!"DEF3" && defined!"Y") || (!defined!"DEF" && !defined!"DEF2" && defined!"DEF3" && !defined!"DEF4" && !defined!"X" && !defined!"Y") || (!defined!"DEF" && defined!"DEF2" && defined!"DEF3" && defined!"DEF4") || (defined!"DEF" && (!defined!"DEF3" || (configValue!"Y" == 2 && !defined!"DEF4" && defined!"Y"))))
{
__gshared int a;
}
static if ((configValue!"X" || defined!"DEF" || defined!"DEF2" || !defined!"DEF3" || defined!"DEF4" || defined!"Y") && (configValue!"X" != 1 || defined!"DEF" || !defined!"DEF3" || !defined!"DEF4" || !defined!"X") && (configValue!"X" != 2 || defined!"DEF2" || defined!"DEF3" || !defined!"X") && (!configValue!"X"==configValue!"Y" || defined!"DEF" || defined!"DEF2" || !defined!"DEF3" || defined!"DEF4" || !defined!"X" || !defined!"Y") && (configValue!"Y" || defined!"DEF" || defined!"DEF2" || !defined!"DEF3" || defined!"DEF4" || defined!"X") && (configValue!"Y" != 1 || defined!"DEF" || !defined!"DEF2" || !defined!"DEF3" || !defined!"Y") && (defined!"DEF" || defined!"DEF2" || !defined!"DEF3" || defined!"DEF4" || defined!"X" || defined!"Y") && (defined!"DEF" || !defined!"DEF2" || !defined!"DEF3" || !defined!"DEF4") && (!defined!"DEF" || (defined!"DEF3" && (configValue!"Y" != 2 || defined!"DEF4" || !defined!"Y"))))
{
__gshared int b;
}

