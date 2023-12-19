#addincludepath "includeoverlay"

#if defined(_WIN32) && !defined(__CYGWIN__)
#addincludepath "../wine/orig/include/msvcrt"
#endif

#if !defined(_WIN32) || defined(__CYGWIN__)
#addincludepath "../gcc-rt/orig/include"
#addincludepath "../gcc-rt/orig/include-fixed"
#endif

#if defined(_WIN32)
#addincludepath "../wine/orig/include/windows"
#endif

#if !defined(_WIN32) || defined(__CYGWIN__)
#addincludepath "../glibc/orig/include"
#endif

#addincludepath "../linuxapi/orig/include"
