module test162;

import config;
import cppconvhelpers;


struct ZSTD_inBuffer_s {
  const(void)* src;    /**< start of input buffer */
  size_t size;        /**< size of input buffer */
  size_t pos;         /**< position where reading stopped. Will be updated. Necessarily 0 <= pos <= size */
}
alias ZSTD_inBuffer = ZSTD_inBuffer_s;

void f(ZSTD_inBuffer);

void drive_compressor(const(void)* src, size_t length)
{
	ZSTD_inBuffer in_ = /+ (ZSTD_inBuffer) +/ ZSTD_inBuffer_s( src, length, 0) ;
	in_ = /+ (ZSTD_inBuffer) +/ ZSTD_inBuffer_s( src, length, 0) ;
	ZSTD_inBuffer[2] in2 = mixin(buildStaticArray!(q{ZSTD_inBuffer}, 2, q{/+ (ZSTD_inBuffer) +/ ZSTD_inBuffer_s( src, length, 0) }));
	in2[0] = /+ (ZSTD_inBuffer) +/ ZSTD_inBuffer_s( src, length, 0) ;
	f(/+ (ZSTD_inBuffer) +/ ZSTD_inBuffer_s( src, length, 0) );
}

