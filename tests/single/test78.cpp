typedef unsigned long size_t;

#define git_array_t(type) struct { type *ptr; size_t size, asize; }

struct git_buf
{
	int x;
};

struct git_repository {
	git_array_t(git_buf) reserved_names;
};
