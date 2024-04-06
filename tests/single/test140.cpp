
struct archive_vtable {
	int	(*archive_close)(struct archive *);
};

struct archive {

	struct archive_vtable *vtable;
};


int
archive_read_close(struct archive *a)
{
	return ((a->vtable->archive_close)(a));
}
