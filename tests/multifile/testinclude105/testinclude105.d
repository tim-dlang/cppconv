module testinclude105;

import config;
import cppconvhelpers;

void free(void*);
void* calloc(uint, uint);
struct kh_str_t
{
    int i;
}
/+ #define kfree free +/
alias kfree = free;
/+ #define kcalloc calloc +/
alias kcalloc = calloc;
int identity(int i)
{
    return i;
}
kh_str_t* kh_init_str(){return cast(kh_str_t*) kcalloc(1,cast(uint) (kh_str_t.sizeof));}
void kh_destroy_str(kh_str_t* h){ kfree(h);}
int kh_get_str(const(kh_str_t)* h, int key){return identity(key);}

/+ __KHASH_IMPL(str, identity) +/
