enum E1
{
#ifdef DEF
E1_A,
#endif
E1_B
};
enum E2
{
E2_A
#ifdef DEF
,E2_B
#endif
};
enum E3
{
E3_A,
#ifdef DEF
E3_B,
#endif
E3_C
};
