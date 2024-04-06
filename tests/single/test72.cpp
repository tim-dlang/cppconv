typedef int dev_t;
typedef int ino_t;
typedef int mode_t;
typedef int nlink_t;
typedef int uid_t;
typedef int gid_t;
typedef int dev_t;
typedef int off_t;
typedef int blksize_t;
typedef int blkcnt_t;

typedef int time_t;
struct timespec {
    time_t          tv_sec;
    long            tv_nsec;
};

struct stat {
   dev_t     st_dev;         /* ID of device containing file */
   ino_t     st_ino;         /* Inode number */
   mode_t    st_mode;        /* File type and mode */
   nlink_t   st_nlink;       /* Number of hard links */
   uid_t     st_uid;         /* User ID of owner */
   gid_t     st_gid;         /* Group ID of owner */
   dev_t     st_rdev;        /* Device ID (if special file) */
   off_t     st_size;        /* Total size, in bytes */
   blksize_t st_blksize;     /* Block size for filesystem I/O */
   blkcnt_t  st_blocks;      /* Number of 512B blocks allocated */

   /* Since Linux 2.6, the kernel supports nanosecond
	  precision for the following timestamp fields.
	  For the details before Linux 2.6, see NOTES. */

   struct timespec st_atim;  /* Time of last access */
   struct timespec st_mtim;  /* Time of last modification */
   struct timespec st_ctim;  /* Time of last status change */

#define st_atime st_atim.tv_sec      /* Backward compatibility */
#define st_mtime st_mtim.tv_sec
#define st_ctime st_ctim.tv_sec
};


int stat(const char *pathname, struct stat *statbuf);

void f()
{
	struct stat s;
	stat("test", &s);
}
