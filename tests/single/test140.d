
module test140;

import config;
import cppconvhelpers;

struct archive_vtable {
	int function(archive* )	archive_close;
}

struct archive {

	archive_vtable* vtable;
}


int
archive_read_close(archive* a)
{
	return (/*(*/a.vtable.archive_close/*)*/(a));
}

