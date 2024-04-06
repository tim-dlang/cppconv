extern "C"
{
/** Valid modes for index and tree entries. */
typedef enum {
	GIT_FILEMODE_UNREADABLE          = 0000000,
	GIT_FILEMODE_TREE                = 0040000,
	GIT_FILEMODE_BLOB                = 0100644,
	GIT_FILEMODE_BLOB_EXECUTABLE     = 0100755,
	GIT_FILEMODE_LINK                = 0120000,
	GIT_FILEMODE_COMMIT              = 0160000,
} git_filemode_t;

typedef enum {
	E2_A          = 0,
	E2_B          = 1,
	E2_C          = 2,
} E2;

extern int printf ( const char * format, ... );
}

int main()
{
	printf("git_filemode_t size %zd\n", sizeof(git_filemode_t));
	printf("E2 size %zd\n", sizeof(E2));

	return 0;
}

