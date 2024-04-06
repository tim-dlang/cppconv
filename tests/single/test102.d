/** Valid modes for index and tree entries. */
module test102;

import config;
import cppconvhelpers;

enum git_filemode_t {
	GIT_FILEMODE_UNREADABLE          = octal!0,
	GIT_FILEMODE_TREE                = octal!40000,
	GIT_FILEMODE_BLOB                = octal!100644,
	GIT_FILEMODE_BLOB_EXECUTABLE     = octal!100755,
	GIT_FILEMODE_LINK                = octal!120000,
	GIT_FILEMODE_COMMIT              = octal!160000,
}
// self alias: alias git_filemode_t = git_filemode_t;

void f(git_filemode_t filemode)
{
	ushort  s = cast(ushort) (filemode);
}

