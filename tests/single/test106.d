module test106;

import config;
import cppconvhelpers;

/+ #define va_start(v,l)	__builtin_va_start(v,l)
#define va_end(v)	__builtin_va_end(v)
#define va_arg(v,l)	__builtin_va_arg(v,l)
#define va_copy(d,s)	__builtin_va_copy(d,s)
#define va_list __builtin_va_list

extern "C"
{ +/
int printf ( const(char)*  format, ... );
void* malloc(uint);
uint strlen(const(char)*);
char* strcat(char* dest, const(char)* src);
int vprintf(const(char)* format, /+ va_list +/ cppconvhelpers.va_list ap);
/+ } +/
alias git_commit_parent_callback = const(int) function(size_t idx, void* payload);

int validate_tree_and_parents(
				     git_commit_parent_callback parent_cb, void* parent_payload
				     )
{
	size_t i;
	int parent;

	i = 0;
	while ((parent = parent_cb(i, parent_payload)) != 0) {
		i++;
	}
	return 0;
}

int git_commit__create_internal(
	git_commit_parent_callback parent_cb,
	void* parent_payload)
{
	return validate_tree_and_parents(parent_cb, parent_payload);
}

struct commit_parent_varargs {
	size_t total;
	/+ va_list +/cppconvhelpers.va_list args;
}
// self alias: alias commit_parent_varargs = commit_parent_varargs;

int commit_parent_from_varargs(size_t curr, void* payload)
{
	commit_parent_varargs* data = cast(commit_parent_varargs*)payload;
	int commit;
	printf("commit_parent_from_varargs curr=%d data->total=%d\n", curr, data.total);
	if (curr >= data.total)
		return 0;
	commit = /+ va_arg(data->args, int) +/cast(int) ( va_arg!(int)(data.args));
	printf("commit_parent_from_varargs commit=%d\n", commit);
	return commit ? commit : 0;
}

int git_commit_create_v(
	size_t parent_count,
	...)
{
	commit_parent_varargs data;

	data.total = parent_count;
	/+ va_start(data.args, parent_count) +/va_start(data.args,parent_count);

	git_commit__create_internal(
		cast(git_commit_parent_callback)&commit_parent_from_varargs, &data);

	/+ va_end(data.args) +/va_end(data.args);
	return 0;
}

int main ()
{
	  git_commit_create_v(3, 20, 21, 22);
	  return 0;
}

