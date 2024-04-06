module test127;

import config;
import cppconvhelpers;

struct git_oid;
struct git_odb_backend {
	int function(
			git_odb_backend* , const(git_oid)* )  exists;
}
int f(
	git_odb_backend* b,
	const(git_oid)* id)
{
	bool found = false;

	found = (b.exists(b, id)) != 0;

	return cast(int)found;
}

