struct S1
{
};
void test1(S1 x){}

typedef struct
{
} S2;
void test2(S2 x){}

typedef struct S3
{
} S3;
void test3(S3 x){}

typedef struct S4
{
} S5;
void test4(S4 x){}
void test5(S5 x){}

struct
{

} s6;
void test6(decltype(s6) x){}
