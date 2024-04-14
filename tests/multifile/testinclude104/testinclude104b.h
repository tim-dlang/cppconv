typedef enum
{
    A,
    B,
#ifdef DEF
    C,
#endif
    D
} E;

typedef struct S
{
    E e;
} S;
