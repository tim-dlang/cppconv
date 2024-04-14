
#define __KHASH_IMPL(name, func) \
	kh_##name##_t *kh_init_##name(void) {							\
		return (kh_##name##_t*)kcalloc(1, sizeof(kh_##name##_t));		\
	}                                                               \
    void kh_destroy_##name(kh_##name##_t *h)						\
	{																	\
        kfree(h);													\
	}                                                               \
	int kh_get_##name(const kh_##name##_t *h, int key) 	\
	{																	\
		return func(key);												\
	}
