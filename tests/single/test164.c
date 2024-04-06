#ifndef __COMPAR_FN_T
# define __COMPAR_FN_T
typedef int (*__compar_fn_t) (const void *, const void *);
#endif

extern void qsort (__compar_fn_t __compar);

int _compare_path_table(const void *v1, const void *v2);

void f()
{
	qsort((__compar_fn_t)_compare_path_table);
	qsort(_compare_path_table);
}
