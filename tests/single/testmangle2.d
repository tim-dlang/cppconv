module testmangle2;

import config;
import cppconvhelpers;

struct S2
{
}
// self alias: alias S2 = S2/+ , +/;
alias PS2 = S2 *;
void test2(S2 x){}
void test2p(PS2 x){}

struct S3
{
}
// self alias: alias S3 = S3/+ , +/;
alias PS3 = S3 *;
void test3(S3 x){}
void test3p(PS3 x){}

struct S4
{
}
alias S5 = S4/+ , +/;
alias PS5 = S4 *;
void test4(S4 x){}
void test5(S5 x){}
void test5p(PS5 x){}

