void f1(int);
void f2(int) noexcept;

void g()
{
    void (*fp1)(int);
    void (*fp2)(int) noexcept;
    void (*fp3[2])(int);
    void (*fp4[2])(int) noexcept;
    void (*const fp5)(int) noexcept = &f2;
    void (*const fp6[2])(int) noexcept = {&f2, &f2};

    fp1 = &f1;
    fp2 = &f2;
    fp3[0] = &f1;
    fp4[0] = &f2;
}
