module test109;

import config;
import cppconvhelpers;

/+ #define NULL 0 +/
enum NULL = null;
extern(D) static __gshared /+ const(char)*/+ const +/ [0]  +/ auto git_generated_prefixes = mixin(buildStaticArray!(q{const(char)*}, q{
	"Signed-off-by: ".ptr,
	"(cherry picked from commit ".ptr,
	NULL}))
;

/+ #define GIT_OBJECTS_DIR "objects/" +/
enum GIT_OBJECTS_DIR = "objects/";
/+ #define GIT_OBJECT_DIR_MODE 0777 +/
enum GIT_OBJECT_DIR_MODE = octal!777;
/+ #define GIT_OBJECT_FILE_MODE 0444 +/

/+ #define GIT_REFS_DIR "refs/" +/
enum GIT_REFS_DIR = "refs/";
/+ #define GIT_REFS_HEADS_DIR GIT_REFS_DIR "heads/" +/
enum GIT_REFS_HEADS_DIR = GIT_REFS_DIR ~ "heads/";
/+ #define GIT_REFS_TAGS_DIR GIT_REFS_DIR "tags/" +/
enum GIT_REFS_TAGS_DIR = GIT_REFS_DIR ~ "tags/";
/+ #define GIT_REFS_REMOTES_DIR GIT_REFS_DIR "remotes/"
#define GIT_REFS_NOTES_DIR GIT_REFS_DIR "notes/" +/
/+ #define GIT_REFS_DIR_MODE 0777 +/
enum GIT_REFS_DIR_MODE = octal!777;
/+ #define GIT_REFS_FILE_MODE 0666 +/

/+ #define GIT_OBJECTS_INFO_DIR GIT_OBJECTS_DIR "info/" +/
enum GIT_OBJECTS_INFO_DIR = GIT_OBJECTS_DIR ~ "info/";
/+ #define GIT_OBJECTS_PACK_DIR GIT_OBJECTS_DIR "pack/" +/
enum GIT_OBJECTS_PACK_DIR = GIT_OBJECTS_DIR ~ "pack/";

/+ #define GIT_HOOKS_DIR "hooks/" +/
enum GIT_HOOKS_DIR = "hooks/";
/+ #define GIT_HOOKS_DIR_MODE 0777 +/
enum GIT_HOOKS_DIR_MODE = octal!777;

/+ #define GIT_HOOKS_README_FILE GIT_HOOKS_DIR "README.sample" +/
enum GIT_HOOKS_README_FILE = GIT_HOOKS_DIR ~ "README.sample";
/+ #define GIT_HOOKS_README_MODE 0777 +/
enum GIT_HOOKS_README_MODE = octal!777;
/+ #define GIT_HOOKS_README_CONTENT \
"#!/bin/sh\n"\
"#\n"\
"# Place appropriately named executable hook scripts into this directory\n"\
"# to intercept various actions that git takes.  See `git help hooks` for\n"\
"# more information.\n" +/
enum GIT_HOOKS_README_CONTENT =
    "#!/bin/sh\n" ~
    "#\n" ~
    "# Place appropriately named executable hook scripts into this directory\n" ~
    "# to intercept various actions that git takes.  See `git help hooks` for\n" ~
    "# more information.\n";

/+ #define GIT_INFO_DIR "info/" +/
enum GIT_INFO_DIR = "info/";
/+ #define GIT_INFO_DIR_MODE 0777 +/
enum GIT_INFO_DIR_MODE = octal!777;

/+ #define GIT_INFO_EXCLUDE_FILE GIT_INFO_DIR "exclude" +/
enum GIT_INFO_EXCLUDE_FILE = GIT_INFO_DIR ~ "exclude";
/+ #define GIT_INFO_EXCLUDE_MODE 0666 +/
enum GIT_INFO_EXCLUDE_MODE = octal!666;
/+ #define GIT_INFO_EXCLUDE_CONTENT \
"# File patterns to ignore; see `git help ignore` for more information.\n"\
"# Lines that start with '#' are comments.\n" +/
enum GIT_INFO_EXCLUDE_CONTENT =
    "# File patterns to ignore; see `git help ignore` for more information.\n" ~
    "# Lines that start with '#' are comments.\n";

/+ #define GIT_DESC_FILE "description" +/
enum GIT_DESC_FILE = "description";
/+ #define GIT_DESC_MODE 0666 +/
enum GIT_DESC_MODE = octal!666;
/+ #define GIT_DESC_CONTENT \
"Unnamed repository; edit this file 'description' to name the repository.\n" +/
enum GIT_DESC_CONTENT =
    "Unnamed repository; edit this file 'description' to name the repository.\n";

alias mode_t = uint;

struct repo_template_item {
	const(char)* path;
	mode_t mode;
	const(char)* content;
}
// self alias: alias repo_template_item = repo_template_item;

extern(D) static __gshared /+ repo_template_item[0]  +/ auto repo_template = mixin(buildStaticArray!(q{repo_template_item}, q{
	repo_template_item( (GIT_OBJECTS_INFO_DIR).ptr, GIT_OBJECT_DIR_MODE, NULL) , /* '/objects/info/' */
	repo_template_item( (GIT_OBJECTS_PACK_DIR).ptr, GIT_OBJECT_DIR_MODE, NULL) , /* '/objects/pack/' */
	repo_template_item( (GIT_REFS_HEADS_DIR).ptr, GIT_REFS_DIR_MODE, NULL) ,     /* '/refs/heads/' */
	repo_template_item( (GIT_REFS_TAGS_DIR).ptr, GIT_REFS_DIR_MODE, NULL) ,      /* '/refs/tags/' */
	repo_template_item( GIT_HOOKS_DIR.ptr, GIT_HOOKS_DIR_MODE, NULL) ,         /* '/hooks/' */
	repo_template_item( GIT_INFO_DIR.ptr, GIT_INFO_DIR_MODE, NULL) ,           /* '/info/' */
	repo_template_item( GIT_DESC_FILE.ptr, GIT_DESC_MODE, GIT_DESC_CONTENT.ptr) ,
	repo_template_item( (GIT_HOOKS_README_FILE).ptr, GIT_HOOKS_README_MODE, (GIT_HOOKS_README_CONTENT).ptr) ,
	repo_template_item( (GIT_INFO_EXCLUDE_FILE).ptr, GIT_INFO_EXCLUDE_MODE, (GIT_INFO_EXCLUDE_CONTENT).ptr) ,
	repo_template_item( NULL, 0, NULL) }))
;

