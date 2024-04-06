typedef unsigned long long size_t;

typedef struct ZSTD_inBuffer_s {
  const void* src;    /**< start of input buffer */
  size_t size;        /**< size of input buffer */
  size_t pos;         /**< position where reading stopped. Will be updated. Necessarily 0 <= pos <= size */
} ZSTD_inBuffer;

void f(ZSTD_inBuffer);

void drive_compressor(const void *src, size_t length)
{
	ZSTD_inBuffer in = (ZSTD_inBuffer) { src, length, 0 };
	in = (ZSTD_inBuffer) { src, length, 0 };
	ZSTD_inBuffer in2[2] = {(ZSTD_inBuffer) { src, length, 0 }};
	in2[0] = (ZSTD_inBuffer) { src, length, 0 };
	f((ZSTD_inBuffer) { src, length, 0 });
}
