module test72;

import config;
import cppconvhelpers;

alias dev_t = int;
alias ino_t = int;
alias mode_t = int;
alias nlink_t = int;
alias uid_t = int;
alias gid_t = int;
/+ typedef int dev_t; +/
alias off_t = int;
alias blksize_t = int;
alias blkcnt_t = int;

alias time_t = int;
struct timespec {
    time_t          tv_sec;
    long            tv_nsec;
}
/+ #define st_atime st_atim.tv_sec      /* Backward compatibility */
#define st_mtime st_mtim.tv_sec
#define st_ctime st_ctim.tv_sec +/

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

   timespec st_atim;  /* Time of last access */
   timespec st_mtim;  /* Time of last modification */
   timespec st_ctim;  /* Time of last status change */

/+ #define st_atime st_atim.tv_sec      /* Backward compatibility */
#define st_mtime st_mtim.tv_sec
#define st_ctime st_ctim.tv_sec +/
}


int stat__1(const(char)* pathname, stat* statbuf);

void f()
{
	stat s;
	stat__1("test", &s);
}

