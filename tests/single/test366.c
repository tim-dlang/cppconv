
typedef struct S_
{
  unsigned NU;
} S;

typedef
  #ifdef DEF
    struct S_ *
  #else
    unsigned
  #endif
  Ref;

#ifdef DEF
  #define NODE(ptr) (ptr)
#else
  #define NODE(offs) ((S *)(p->Base + (offs)))
#endif

typedef struct
{
  unsigned char *Base;
} X;


void f(X *p, Ref n)
{
    S *node = NODE(n);
    unsigned nu = (unsigned)node->NU;
    S *node2 = NODE(n) + nu;
}
