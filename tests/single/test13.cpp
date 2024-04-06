int f1();
#ifdef DEF
extern "C"
{
#endif

int f2();

#ifdef DEF2
extern "C++"
{
#endif

int f3();
#ifdef DEF3
int f4();
#endif
int f5();

#ifdef DEF2
}
#endif

int f6();

#ifdef DEF
}
#endif
int f7();
