int f1();

#ifdef DEF
extern "C"
{
#endif

int f2();
#ifdef DEF2
int f3();
#endif
int f4();

#ifdef DEF
}
#endif

int f5();
