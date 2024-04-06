#ifdef DEF
int a;
#else
typedef int a;
#endif
void f()
{
  if (2 != (a) -1)
  {}
}
