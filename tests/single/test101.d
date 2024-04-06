module test101;

import config;
import cppconvhelpers;

/+ extern "C"
{ +/
/** Valid modes for index and tree entries. */
enum git_filemode_t {
	GIT_FILEMODE_UNREADABLE          = octal!0,
	GIT_FILEMODE_TREE                = octal!40000,
	GIT_FILEMODE_BLOB                = octal!100644,
	GIT_FILEMODE_BLOB_EXECUTABLE     = octal!100755,
	GIT_FILEMODE_LINK                = octal!120000,
	GIT_FILEMODE_COMMIT              = octal!160000,
}
// self alias: alias git_filemode_t = git_filemode_t;

enum E2 {
	E2_A          = 0,
	E2_B          = 1,
	E2_C          = 2,
}
// self alias: alias E2 = E2;

int printf ( const(char)*  format, ... );
/+ } +/

int main()
{
	printf("git_filemode_t size %zd\n", git_filemode_t.sizeof);
	printf("E2 size %zd\n", E2.sizeof);

	return 0;
}

