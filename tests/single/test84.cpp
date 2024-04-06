#define NULL 0

typedef enum {
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
} git_repository_item_t;

static const struct {
    git_repository_item_t parent;
    const char *name;
    bool directory;
} items[] = {
	{ GIT_REPOSITORY_ITEM_GITDIR, NULL, true },
	{ GIT_REPOSITORY_ITEM_WORKDIR, NULL, true },
	{ GIT_REPOSITORY_ITEM_COMMONDIR, NULL, true },
	{ GIT_REPOSITORY_ITEM_GITDIR, "index", false },
	{ GIT_REPOSITORY_ITEM_COMMONDIR, "objects", true },
	{ GIT_REPOSITORY_ITEM_COMMONDIR, "refs", true },
	{ GIT_REPOSITORY_ITEM_COMMONDIR, "packed-refs", false },
	{ GIT_REPOSITORY_ITEM_COMMONDIR, "remotes", true },
	{ GIT_REPOSITORY_ITEM_COMMONDIR, "config", false },
	{ GIT_REPOSITORY_ITEM_COMMONDIR, "info", true },
	{ GIT_REPOSITORY_ITEM_COMMONDIR, "hooks", true },
	{ GIT_REPOSITORY_ITEM_COMMONDIR, "logs", true },
	{ GIT_REPOSITORY_ITEM_GITDIR, "modules", true },
	{ GIT_REPOSITORY_ITEM_COMMONDIR, "worktrees", true }
};

static signed char from_hex[] = {
-1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, /* 00 */
-1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, /* 10 */
-1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, /* 20 */
 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, -1, -1, -1, -1, -1, -1, /* 30 */
-1, 10, 11, 12, 13, 14, 15, -1, -1, -1, -1, -1, -1, -1, -1, -1, /* 40 */
-1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, /* 50 */
-1, 10, 11, 12, 13, 14, 15, -1, -1, -1, -1, -1, -1, -1, -1, -1, /* 60 */
-1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, /* 70 */
-1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, /* 80 */
-1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, /* 90 */
-1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, /* a0 */
-1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, /* b0 */
-1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, /* c0 */
-1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, /* d0 */
-1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, /* e0 */
-1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, /* f0 */
};

int m[][2] = {{ 1, 2 }, { 3, 4 }};
char s[] = "Hello world\n";
