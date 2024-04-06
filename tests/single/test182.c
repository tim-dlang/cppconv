
#ifdef DEF
int git_mutex_lock2(int);
#define git_mutex_lock(mtx) git_mutex_lock2(mtx)
#else
int git_mutex_lock(int);
#endif

#define GIT_PACKBUILDER__MUTEX_OP(mtx, op) do { \
		int result = git_mutex_##op(mtx); \
	} while (0)

void f(int progress_mutex)
{
GIT_PACKBUILDER__MUTEX_OP(progress_mutex, lock);
}
