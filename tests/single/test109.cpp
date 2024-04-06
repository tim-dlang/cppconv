#define NULL 0
static const char *const git_generated_prefixes[] = {
	"Signed-off-by: ",
	"(cherry picked from commit ",
	NULL
};

#define GIT_OBJECTS_DIR "objects/"
#define GIT_OBJECT_DIR_MODE 0777
#define GIT_OBJECT_FILE_MODE 0444

#define GIT_REFS_DIR "refs/"
#define GIT_REFS_HEADS_DIR GIT_REFS_DIR "heads/"
#define GIT_REFS_TAGS_DIR GIT_REFS_DIR "tags/"
#define GIT_REFS_REMOTES_DIR GIT_REFS_DIR "remotes/"
#define GIT_REFS_NOTES_DIR GIT_REFS_DIR "notes/"
#define GIT_REFS_DIR_MODE 0777
#define GIT_REFS_FILE_MODE 0666

#define GIT_OBJECTS_INFO_DIR GIT_OBJECTS_DIR "info/"
#define GIT_OBJECTS_PACK_DIR GIT_OBJECTS_DIR "pack/"

#define GIT_HOOKS_DIR "hooks/"
#define GIT_HOOKS_DIR_MODE 0777

#define GIT_HOOKS_README_FILE GIT_HOOKS_DIR "README.sample"
#define GIT_HOOKS_README_MODE 0777
#define GIT_HOOKS_README_CONTENT \
"#!/bin/sh\n"\
"#\n"\
"# Place appropriately named executable hook scripts into this directory\n"\
"# to intercept various actions that git takes.  See `git help hooks` for\n"\
"# more information.\n"

#define GIT_INFO_DIR "info/"
#define GIT_INFO_DIR_MODE 0777

#define GIT_INFO_EXCLUDE_FILE GIT_INFO_DIR "exclude"
#define GIT_INFO_EXCLUDE_MODE 0666
#define GIT_INFO_EXCLUDE_CONTENT \
"# File patterns to ignore; see `git help ignore` for more information.\n"\
"# Lines that start with '#' are comments.\n"

#define GIT_DESC_FILE "description"
#define GIT_DESC_MODE 0666
#define GIT_DESC_CONTENT \
"Unnamed repository; edit this file 'description' to name the repository.\n"

typedef unsigned mode_t;

typedef struct {
	const char *path;
	mode_t mode;
	const char *content;
} repo_template_item;

static repo_template_item repo_template[] = {
	{ GIT_OBJECTS_INFO_DIR, GIT_OBJECT_DIR_MODE, NULL }, /* '/objects/info/' */
	{ GIT_OBJECTS_PACK_DIR, GIT_OBJECT_DIR_MODE, NULL }, /* '/objects/pack/' */
	{ GIT_REFS_HEADS_DIR, GIT_REFS_DIR_MODE, NULL },     /* '/refs/heads/' */
	{ GIT_REFS_TAGS_DIR, GIT_REFS_DIR_MODE, NULL },      /* '/refs/tags/' */
	{ GIT_HOOKS_DIR, GIT_HOOKS_DIR_MODE, NULL },         /* '/hooks/' */
	{ GIT_INFO_DIR, GIT_INFO_DIR_MODE, NULL },           /* '/info/' */
	{ GIT_DESC_FILE, GIT_DESC_MODE, GIT_DESC_CONTENT },
	{ GIT_HOOKS_README_FILE, GIT_HOOKS_README_MODE, GIT_HOOKS_README_CONTENT },
	{ GIT_INFO_EXCLUDE_FILE, GIT_INFO_EXCLUDE_MODE, GIT_INFO_EXCLUDE_CONTENT },
	{ NULL, 0, NULL }
};
