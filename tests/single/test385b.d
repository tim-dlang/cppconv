module test385b;
extern(C++):

import config;
import cppconvhelpers;

void f1(int);
void f2(int) nothrow;

void g()
{
    ExternCPPFunc!(void function(int)) fp1;
    ExternCPPFunc!(void function(int) nothrow) fp2;
    ExternCPPFunc!(void function(int))[2] fp3;
    ExternCPPFunc!(void function(int) nothrow)[2] fp4;
    const(ExternCPPFunc!(void function(int) nothrow) ) fp5 = &f2;
    const(ExternCPPFunc!(void function(int) nothrow) )[2] fp6 = [&f2, &f2];

    fp1 = &f1;
    fp2 = &f2;
    fp3[0] = &f1;
    fp4[0] = &f2;
}

