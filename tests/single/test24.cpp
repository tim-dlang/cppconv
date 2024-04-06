#ifndef D
#define D

#ifdef D
void a();
#else
void b();
#endif

#ifndef D
void c();
#else
void d();
#endif

#endif
