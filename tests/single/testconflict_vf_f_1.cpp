typedef int I;
void f()
{
double x(I),
#ifndef DEF
I
#else
dummy
#endif
, y(I);
}
