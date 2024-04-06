module testtypedef1;

import config;
import cppconvhelpers;

struct git_oidarray {
	char* ids;
	int count;
}
// self alias: alias git_oidarray = git_oidarray;

void f(git_oidarray x);

__gshared git_oidarray a;

