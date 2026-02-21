void f1(int);
void f2(int) noexcept;

class C
{
public:
    void f1();
    void f2() noexcept;
    void f3() const;
    void f4() const noexcept;
};

void g()
{
    void (*fp1)(int);
    void (*fp2)(int) noexcept;
    void (*fp3[2])(int);
    void (*fp4[2])(int) noexcept;

    fp1 = &f1;
    fp2 = &f2;
    fp3[0] = &f1;
    fp4[0] = &f2;
}
