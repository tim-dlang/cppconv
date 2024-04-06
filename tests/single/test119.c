#ifdef _WIN32
#define open _open
#endif
typedef enum {
	/** System-wide on Windows, for compatibility with portable git */
	GIT_CONFIG_LEVEL_PROGRAMDATA = 1,

	/** System-wide configuration file; /etc/gitconfig on Linux systems */
	GIT_CONFIG_LEVEL_SYSTEM = 2,

	/** XDG compatible configuration file; typically ~/.config/git/config */
	GIT_CONFIG_LEVEL_XDG = 3,

	/** User-specific configuration file (also called Global configuration
	 * file); typically ~/.gitconfig
	 */
	GIT_CONFIG_LEVEL_GLOBAL = 4,

	/** Repository specific configuration file; $WORK_DIR/.git/config on
	 * non-bare repos
	 */
	GIT_CONFIG_LEVEL_LOCAL = 5,

	/** Application specific configuration file; freely defined by applications
	 */
	GIT_CONFIG_LEVEL_APP = 6,

	/** Represents the highest level available config file (i.e. the most
	 * specific config file available that actually is loaded)
	 */
	GIT_CONFIG_HIGHEST_LEVEL = -1,
} git_config_level_t;

typedef struct git_repository git_repository;

typedef struct git_config_backend git_config_backend;
struct git_config_backend {
	int (*open)(struct git_config_backend *, git_config_level_t level, const git_repository *repo);
};

int git_config_file_open(git_config_backend *cfg, unsigned int level, const git_repository *repo)
{
	return cfg->open(cfg, level, repo);
}
