#ifdef DEF
int a;
#else
typedef int a;
#endif
#ifdef DEF
int b;
#else
typedef int b;
#endif
void f()
{
  if ((b) - 1 != (a) - 1)
  {}
}
