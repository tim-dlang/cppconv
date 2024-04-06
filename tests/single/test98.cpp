#define	__S_IFMT	0170000
#define	__S_IFLNK	0120000
#define	__S_ISTYPE(mode, mask)	(((mode) & __S_IFMT) == (mask))
# define S_ISLNK(mode)	 __S_ISTYPE((mode), __S_IFLNK)
void f(int mode){
	if (S_ISLNK(mode));
}
