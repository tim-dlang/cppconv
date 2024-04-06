
#define BAD_CAST (char *)

void g(char *);

void f()
{
    g(BAD_CAST "test");
}
