module test119;

import config;
import cppconvhelpers;

/+ #ifdef _WIN32
#define open _open
#endif +/
enum git_config_level_t {
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
}
// self alias: alias git_config_level_t = git_config_level_t;
struct git_repository;
// self alias: alias git_repository = git_repository;

// self alias: alias git_config_backend = git_config_backend;
struct git_config_backend {
	static if (defined!"_WIN32")
	{
	int function(git_config_backend* , git_config_level_t level, const(git_repository)* repo) _open;
	}
static if (!defined!"_WIN32")
{
int function(git_config_backend*, git_config_level_t level, const(git_repository)* repo) open;
}
}

int git_config_file_open(git_config_backend* cfg, uint  level, const(git_repository)* repo)
{
	return mixin(q{cfg
}
 ~ ((defined!"_WIN32") ? "._open" : ".open"))(cfg, cast(git_config_level_t) (level), repo);
}

