
module test182;

import config;
import cppconvhelpers;

static if (defined!"DEF")
{
int git_mutex_lock2(int);
/+ #define git_mutex_lock(mtx) git_mutex_lock2(mtx) +/
extern(D) alias git_mutex_lock = function string(string mtx)
{
    return mixin(interpolateMixin(q{git_mutex_lock2($(mtx))}));
};
}
static if (!defined!"DEF")
{
int git_mutex_lock(int);
}

/+ #define GIT_PACKBUILDER__MUTEX_OP(mtx, op) do { \
		int result = git_mutex_##op(mtx); \
	} while (0) +/

void f(int progress_mutex)
{
/+ GIT_PACKBUILDER__MUTEX_OP(progress_mutex, lock) +/do{int result= mixin((defined!"DEF") ? q{
        mixin(git_mutex_lock(q{progress_mutex}))
    } : q{
        git_mutex_lock(progress_mutex)
    });}while(0);
}

