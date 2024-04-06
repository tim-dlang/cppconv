module test78;

import config;
import cppconvhelpers;


/+ #define git_array_t(type) struct { type *ptr; size_t size, asize; } +/

struct git_buf
{
	int x;
}

struct git_repository {
	/+ git_array_t(git_buf) +/struct generated_test78_git_array_t_0{git_buf* ptr;size_t size;size_t asize;}generated_test78_git_array_t_0 reserved_names;
}

