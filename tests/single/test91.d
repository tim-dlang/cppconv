module test91;

import config;
import cppconvhelpers;

/+ #define offsetof(TYPE, MEMBER) __builtin_offsetof (TYPE, MEMBER) +/

struct entry_long
{
	int i;
	const(char)* path;
}

ulong  index_entry_size()
{
	return /+ offsetof(struct entry_long, path) +/entry_long.path.offsetof;
}

