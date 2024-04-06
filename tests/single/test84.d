module test84;

import config;
import cppconvhelpers;

/+ #define NULL 0 +/
enum NULL = null;

enum git_repository_item_t {
        GIT_REPOSITORY_ITEM_GITDIR,
        GIT_REPOSITORY_ITEM_WORKDIR,
        GIT_REPOSITORY_ITEM_COMMONDIR,
        GIT_REPOSITORY_ITEM_INDEX,
        GIT_REPOSITORY_ITEM_OBJECTS,
        GIT_REPOSITORY_ITEM_REFS,
        GIT_REPOSITORY_ITEM_PACKED_REFS,
        GIT_REPOSITORY_ITEM_REMOTES,
        GIT_REPOSITORY_ITEM_CONFIG,
        GIT_REPOSITORY_ITEM_INFO,
        GIT_REPOSITORY_ITEM_HOOKS,
        GIT_REPOSITORY_ITEM_LOGS,
        GIT_REPOSITORY_ITEM_MODULES,
        GIT_REPOSITORY_ITEM_WORKTREES
}
// self alias: alias git_repository_item_t = git_repository_item_t;

struct generated_test84_0 {
    git_repository_item_t parent;
    const(char)* name;
    bool directory;
}
extern(D) static __gshared /+ const(generated_test84_0)[0]  +/ auto items = mixin(buildStaticArray!(q{const(generated_test84_0)}, q{
	const(generated_test84_0)( git_repository_item_t.GIT_REPOSITORY_ITEM_GITDIR, NULL, true) ,
	const(generated_test84_0)( git_repository_item_t.GIT_REPOSITORY_ITEM_WORKDIR, NULL, true) ,
	const(generated_test84_0)( git_repository_item_t.GIT_REPOSITORY_ITEM_COMMONDIR, NULL, true) ,
	const(generated_test84_0)( git_repository_item_t.GIT_REPOSITORY_ITEM_GITDIR, "index".ptr, false) ,
	const(generated_test84_0)( git_repository_item_t.GIT_REPOSITORY_ITEM_COMMONDIR, "objects".ptr, true) ,
	const(generated_test84_0)( git_repository_item_t.GIT_REPOSITORY_ITEM_COMMONDIR, "refs".ptr, true) ,
	const(generated_test84_0)( git_repository_item_t.GIT_REPOSITORY_ITEM_COMMONDIR, "packed-refs".ptr, false) ,
	const(generated_test84_0)( git_repository_item_t.GIT_REPOSITORY_ITEM_COMMONDIR, "remotes".ptr, true) ,
	const(generated_test84_0)( git_repository_item_t.GIT_REPOSITORY_ITEM_COMMONDIR, "config".ptr, false) ,
	const(generated_test84_0)( git_repository_item_t.GIT_REPOSITORY_ITEM_COMMONDIR, "info".ptr, true) ,
	const(generated_test84_0)( git_repository_item_t.GIT_REPOSITORY_ITEM_COMMONDIR, "hooks".ptr, true) ,
	const(generated_test84_0)( git_repository_item_t.GIT_REPOSITORY_ITEM_COMMONDIR, "logs".ptr, true) ,
	const(generated_test84_0)( git_repository_item_t.GIT_REPOSITORY_ITEM_GITDIR, "modules".ptr, true) ,
	const(generated_test84_0)( git_repository_item_t.GIT_REPOSITORY_ITEM_COMMONDIR, "worktrees".ptr, true) }))
;

extern(D) static __gshared /+ byte[0]   +/ auto from_hex = mixin(buildStaticArray!(q{byte}, q{
cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), /* 00 */
cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), /* 10 */
cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), /* 20 */
 cast(byte) (0), cast(byte) (1), cast(byte) (2), cast(byte) (3), cast(byte) (4), cast(byte) (5), cast(byte) (6), cast(byte) (7), cast(byte) (8), cast(byte) (9), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), /* 30 */
cast(byte) (-1), cast(byte) (10), cast(byte) (11), cast(byte) (12), cast(byte) (13), cast(byte) (14), cast(byte) (15), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), /* 40 */
cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), /* 50 */
cast(byte) (-1), cast(byte) (10), cast(byte) (11), cast(byte) (12), cast(byte) (13), cast(byte) (14), cast(byte) (15), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), /* 60 */
cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), /* 70 */
cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), /* 80 */
cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), /* 90 */
cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), /* a0 */
cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), /* b0 */
cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), /* c0 */
cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), /* d0 */
cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), /* e0 */
cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1), cast(byte) (-1),})) /* f0 */
;

__gshared /+ int[2][0]  +/ auto m = mixin(buildStaticArray!(q{int[2]}, q{[ 1, 2] , [ 3, 4] }));
__gshared /+ char[0]  +/ auto s = staticString!(char, "Hello world\n");

