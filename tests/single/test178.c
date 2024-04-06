typedef unsigned long size_t;

typedef void *(*xmlMallocFunc)(size_t size);

void *xmlMallocLoc (size_t size, const char *file, int line);

#ifdef DEBUG_MEMORY_LOCATION
#define xmlMalloc(size) xmlMallocLoc((size), __FILE__, __LINE__)
#endif /* DEBUG_MEMORY_LOCATION */

#undef	xmlMalloc

#ifdef LIBXML_THREAD_ALLOC_ENABLED
#ifdef LIBXML_THREAD_ENABLED
xmlMallocFunc *__xmlMalloc(void);
#define xmlMalloc \
(*(__xmlMalloc()))
#else
xmlMallocFunc xmlMalloc;
#endif
#else /* !LIBXML_THREAD_ALLOC_ENABLED */
xmlMallocFunc xmlMalloc;
#endif /* LIBXML_THREAD_ALLOC_ENABLED */

struct S1
{
	int i;
};

void f1()
{
	struct S1 *x;
	x = (struct S1*) xmlMalloc(sizeof(struct S1));
}

struct S2
{
	int i;
};

void f2()
{
	struct S2 *x;
	x = xmlMalloc(sizeof(struct S2));
}
