#include "testinclude105b.h"

void free(void*);
void *calloc(unsigned, unsigned);
typedef struct kh_str_t
{
    int i;
} kh_str_t;

#define kfree free
#define kcalloc calloc
