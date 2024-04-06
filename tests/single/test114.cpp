#define NULL 0

typedef struct transport_definition {
	char *prefix;
} transport_definition;

static transport_definition transports[] = {
	{ "git://" },
	{ "http://" },
	{ "https://" },
	{ "file://" },
#ifdef GIT_SSH
	{ "ssh://" },
	{ "ssh+git://" },
	{ "git+ssh://" },
#endif
	{ NULL }
};
