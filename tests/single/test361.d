module test361;

import config;
import cppconvhelpers;

/+ #ifdef ALWAYS_PREDEFINED_IN_TEST
#unknown X1
#unknown X2
#unknown X3
#unknown X4
#unknown X5
#endif +/

static if (configValue!"X1" == 1)
{
void f1();
}
static if (configValue!"X1" == 2)
{
void f1();
}

static if (configValue!"X2" == 1)
{
void f2();
}
static if (configValue!"X2" == 2)
{
void f2();
}

static if (configValue!"X3" == 1)
{
void f3();
}
static if (configValue!"X3" == 2)
{
void f3();
}

static if (configValue!"X4" == 1)
{
void f4();
}
static if (configValue!"X4" == 2)
{
void f4();
}

static if (configValue!"X5" == 1)
{
void f5();
}
static if (configValue!"X5" == 2)
{
void f5();
}

