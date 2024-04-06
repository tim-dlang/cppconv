module testmangle1;

import config;
import cppconvhelpers;

struct S1
{
}
void test1(S1 x){}

struct S2
{
}
// self alias: alias S2 = S2;
void test2(S2 x){}

struct S3
{
}
// self alias: alias S3 = S3;
void test3(S3 x){}

struct S4
{
}
alias S5 = S4;
void test4(S4 x){}
void test5(S5 x){}

struct generated_testmangle1_0
{

}
__gshared generated_testmangle1_0 s6;
void test6(/+ decltype(s6) +/ generated_testmangle1_0 x){}

