class C
{
};
C *createC();
void f()
{
    if (C *x = createC())
    {}
}
