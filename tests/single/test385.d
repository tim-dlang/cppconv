module test385;

import config;
import cppconvhelpers;

void f1(int);
void f2(int) nothrow;

extern(C++, class) struct C
{
public:
    void f1();
    void f2() nothrow;
    void f3() const;
    void f4() const nothrow;
}

void g()
{
    void function(int) fp1;
    void function(int) nothrow fp2;
    void function(int)[2] fp3;
    void function(int) nothrow[2] fp4;

    fp1 = &f1;
    fp2 = &f2;
    fp3[0] = &f1;
    fp4[0] = &f2;
}

