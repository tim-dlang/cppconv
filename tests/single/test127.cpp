struct git_oid;
struct git_odb_backend {
	int (* exists)(
		git_odb_backend *, const git_oid *);
};
static int f(
	git_odb_backend *b,
	const git_oid *id)
{
	bool found = false;

	found = b->exists(b, id);

	return (int)found;
}
