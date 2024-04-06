#define offsetof(TYPE, MEMBER) __builtin_offsetof (TYPE, MEMBER)

struct entry_long
{
	int i;
	const char *path;
};

static unsigned long index_entry_size()
{
	return offsetof(struct entry_long, path);
}
