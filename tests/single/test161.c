typedef int dev_t;

typedef	dev_t pack_t(int, unsigned long [], const char **);

pack_t	*pack_find(const char *);
pack_t	 pack_native;
