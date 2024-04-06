#	define TUKLIB_SYMBOL_PREFIX

#define TUKLIB_CAT_X(a, b) a ## b
#define TUKLIB_CAT(a, b) TUKLIB_CAT_X(a, b)

#	define TUKLIB_SYMBOL(sym) TUKLIB_CAT(TUKLIB_SYMBOL_PREFIX, sym)

#define tuklib_physmem TUKLIB_SYMBOL(tuklib_physmem)
extern unsigned long tuklib_physmem(void);

void f()
{
	tuklib_physmem();
}
