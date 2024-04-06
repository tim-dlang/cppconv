/*-
* Copyright (c) 2003-2007 Tim Kientzle
* Copyright (c) 2011 Andres Mejia
* Copyright (c) 2011 Michihiro NAKAJIMA
* All rights reserved.
*
* Redistribution and use in source and binary forms, with or without
* modification, are permitted provided that the following conditions
* are met:
* 1. Redistributions of source code must retain the above copyright
*    notice, this list of conditions and the following disclaimer.
* 2. Redistributions in binary form must reproduce the above copyright
*    notice, this list of conditions and the following disclaimer in the
*    documentation and/or other materials provided with the distribution.
*
* THIS SOFTWARE IS PROVIDED BY THE AUTHOR(S) ``AS IS'' AND ANY EXPRESS OR
* IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
* OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
* IN NO EVENT SHALL THE AUTHOR(S) BE LIABLE FOR ANY DIRECT, INDIRECT,
* INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
* NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
* DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
* THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
* (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
* THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

typedef unsigned long size_t;

typedef unsigned char archive_md5_ctx;
typedef unsigned char archive_rmd160_ctx;
typedef unsigned char archive_sha1_ctx;
typedef unsigned char archive_sha256_ctx;
typedef unsigned char archive_sha384_ctx;
typedef unsigned char archive_sha512_ctx;

/* Minimal interface to digest functionality for internal use in libarchive */
struct archive_digest
{
  /* Message Digest */
  int (*md5init)(archive_md5_ctx *ctx);
  int (*md5update)(archive_md5_ctx *, const void *, size_t);
  int (*md5final)(archive_md5_ctx *, void *);
  int (*rmd160init)(archive_rmd160_ctx *);
  int (*rmd160update)(archive_rmd160_ctx *, const void *, size_t);
  int (*rmd160final)(archive_rmd160_ctx *, void *);
  int (*sha1init)(archive_sha1_ctx *);
  int (*sha1update)(archive_sha1_ctx *, const void *, size_t);
  int (*sha1final)(archive_sha1_ctx *, void *);
  int (*sha256init)(archive_sha256_ctx *);
  int (*sha256update)(archive_sha256_ctx *, const void *, size_t);
  int (*sha256final)(archive_sha256_ctx *, void *);
  int (*sha384init)(archive_sha384_ctx *);
  int (*sha384update)(archive_sha384_ctx *, const void *, size_t);
  int (*sha384final)(archive_sha384_ctx *, void *);
  int (*sha512init)(archive_sha512_ctx *);
  int (*sha512update)(archive_sha512_ctx *, const void *, size_t);
  int (*sha512final)(archive_sha512_ctx *, void *);
};

extern const struct archive_digest __archive_digest;

/* MD5 implementations */
#if defined(ARCHIVE_CRYPTO_MD5_LIBC)
static int __archive_libc_md5init(archive_md5_ctx *ctx);
static int __archive_libc_md5update(archive_md5_ctx *ctx, const void *indata, size_t insize);
static int __archive_libc_md5final(archive_md5_ctx *ctx, void *md);
#elif defined(ARCHIVE_CRYPTO_MD5_LIBMD)
static int __archive_libmd_md5init(archive_md5_ctx *ctx);
static int __archive_libmd_md5update(archive_md5_ctx *ctx, const void *indata, size_t insize);
static int __archive_libmd_md5final(archive_md5_ctx *ctx, void *md);
#elif defined(ARCHIVE_CRYPTO_MD5_LIBSYSTEM)
static int __archive_libsystem_md5init(archive_md5_ctx *ctx);
static int __archive_libsystem_md5update(archive_md5_ctx *ctx, const void *indata, size_t insize);
static int __archive_libsystem_md5final(archive_md5_ctx *ctx, void *md);
#elif defined(ARCHIVE_CRYPTO_MD5_MBEDTLS)
static int __archive_mbedtls_md5init(archive_md5_ctx *ctx);
static int __archive_mbedtls_md5update(archive_md5_ctx *ctx, const void *indata, size_t insize);
static int __archive_mbedtls_md5final(archive_md5_ctx *ctx, void *md);
#elif defined(ARCHIVE_CRYPTO_MD5_NETTLE)
static int __archive_nettle_md5init(archive_md5_ctx *ctx);
static int __archive_nettle_md5update(archive_md5_ctx *ctx, const void *indata, size_t insize);
static int __archive_nettle_md5final(archive_md5_ctx *ctx, void *md);
#elif defined(ARCHIVE_CRYPTO_MD5_OPENSSL)
static int __archive_openssl_md5init(archive_md5_ctx *ctx);
static int __archive_openssl_md5update(archive_md5_ctx *ctx, const void *indata, size_t insize);
static int __archive_openssl_md5final(archive_md5_ctx *ctx, void *md);
#elif defined(ARCHIVE_CRYPTO_MD5_WIN)
static int __archive_windowsapi_md5init(archive_md5_ctx *ctx);
static int __archive_windowsapi_md5update(archive_md5_ctx *ctx, const void *indata, size_t insize);
static int __archive_windowsapi_md5final(archive_md5_ctx *ctx, void *md);
#else
static int __archive_stub_md5init(archive_md5_ctx *ctx);
static int __archive_stub_md5update(archive_md5_ctx *ctx, const void *indata, size_t insize);
static int __archive_stub_md5final(archive_md5_ctx *ctx, void *md);
#endif

/* RIPEMD160 implementations */
#if defined(ARCHIVE_CRYPTO_RMD160_LIBC)
static int __archive_libc_ripemd160init(archive_rmd160_ctx *ctx);
static int __archive_libc_ripemd160update(archive_rmd160_ctx *ctx, const void *indata, size_t insize);
static int __archive_libc_ripemd160final(archive_rmd160_ctx *ctx, void *md);
#elif defined(ARCHIVE_CRYPTO_RMD160_LIBMD)
static int __archive_libmd_ripemd160init(archive_rmd160_ctx *ctx);
static int __archive_libmd_ripemd160update(archive_rmd160_ctx *ctx, const void *indata, size_t insize);
static int __archive_libmd_ripemd160final(archive_rmd160_ctx *ctx, void *md);
#elif defined(ARCHIVE_CRYPTO_RMD160_MBEDTLS)
static int __archive_mbedtls_ripemd160init(archive_rmd160_ctx *ctx);
static int
__archive_mbedtls_ripemd160update(archive_rmd160_ctx *ctx, const void *indata, size_t insize);
static int __archive_mbedtls_ripemd160final(archive_rmd160_ctx *ctx, void *md);
#elif defined(ARCHIVE_CRYPTO_RMD160_NETTLE)
static int __archive_nettle_ripemd160init(archive_rmd160_ctx *ctx);
static int __archive_nettle_ripemd160update(archive_rmd160_ctx *ctx, const void *indata, size_t insize);
static int __archive_nettle_ripemd160final(archive_rmd160_ctx *ctx, void *md);
#elif defined(ARCHIVE_CRYPTO_RMD160_OPENSSL)
static int __archive_openssl_ripemd160init(archive_rmd160_ctx *ctx);
static int __archive_openssl_ripemd160update(archive_rmd160_ctx *ctx, const void *indata, size_t insize);
static int __archive_openssl_ripemd160final(archive_rmd160_ctx *ctx, void *md);
#else
static int __archive_stub_ripemd160init(archive_rmd160_ctx *ctx);
static int __archive_stub_ripemd160update(archive_rmd160_ctx *ctx, const void *indata, size_t insize);
static int __archive_stub_ripemd160final(archive_rmd160_ctx *ctx, void *md);
#endif

/* SHA1 implementations */
#if defined(ARCHIVE_CRYPTO_SHA1_LIBC)
static int __archive_libc_sha1init(archive_sha1_ctx *ctx);
static int __archive_libc_sha1update(archive_sha1_ctx *ctx, const void *indata, size_t insize);
static int __archive_libc_sha1final(archive_sha1_ctx *ctx, void *md);
#elif defined(ARCHIVE_CRYPTO_SHA1_LIBMD)
static int __archive_libmd_sha1init(archive_sha1_ctx *ctx);
static int __archive_libmd_sha1update(archive_sha1_ctx *ctx, const void *indata, size_t insize);
static int __archive_libmd_sha1final(archive_sha1_ctx *ctx, void *md);
#elif defined(ARCHIVE_CRYPTO_SHA1_LIBSYSTEM)
static int __archive_libsystem_sha1init(archive_sha1_ctx *ctx);
static int __archive_libsystem_sha1update(archive_sha1_ctx *ctx, const void *indata, size_t insize);
static int __archive_libsystem_sha1final(archive_sha1_ctx *ctx, void *md);
#elif defined(ARCHIVE_CRYPTO_SHA1_MBEDTLS)
static int __archive_mbedtls_sha1init(archive_sha1_ctx *ctx);
static int __archive_mbedtls_sha1update(archive_sha1_ctx *ctx, const void *indata, size_t insize);
static int __archive_mbedtls_sha1final(archive_sha1_ctx *ctx, void *md);
#elif defined(ARCHIVE_CRYPTO_SHA1_NETTLE)
static int __archive_nettle_sha1init(archive_sha1_ctx *ctx);
static int __archive_nettle_sha1update(archive_sha1_ctx *ctx, const void *indata, size_t insize);
static int __archive_nettle_sha1final(archive_sha1_ctx *ctx, void *md);
#elif defined(ARCHIVE_CRYPTO_SHA1_OPENSSL)
static int __archive_openssl_sha1init(archive_sha1_ctx *ctx);
static int __archive_openssl_sha1update(archive_sha1_ctx *ctx, const void *indata, size_t insize);
static int __archive_openssl_sha1final(archive_sha1_ctx *ctx, void *md);
#elif defined(ARCHIVE_CRYPTO_SHA1_WIN)
static int __archive_windowsapi_sha1init(archive_sha1_ctx *ctx);
static int __archive_windowsapi_sha1update(archive_sha1_ctx *ctx, const void *indata, size_t insize);
static int __archive_windowsapi_sha1final(archive_sha1_ctx *ctx, void *md);
#else
static int __archive_stub_sha1init(archive_sha1_ctx *ctx);
static int __archive_stub_sha1update(archive_sha1_ctx *ctx, const void *indata, size_t insize);
static int __archive_stub_sha1final(archive_sha1_ctx *ctx, void *md);
#endif

/* SHA256 implementations */
#if defined(ARCHIVE_CRYPTO_SHA256_LIBC)
static int __archive_libc_sha256init(archive_sha256_ctx *ctx);
static int __archive_libc_sha256update(archive_sha256_ctx *ctx, const void *indata, size_t insize);
static int __archive_libc_sha256final(archive_sha256_ctx *ctx, void *md);
#elif defined(ARCHIVE_CRYPTO_SHA256_LIBC2)
static int __archive_libc2_sha256init(archive_sha256_ctx *ctx);
static int __archive_libc2_sha256update(archive_sha256_ctx *ctx, const void *indata, size_t insize);
static int __archive_libc2_sha256final(archive_sha256_ctx *ctx, void *md);
#elif defined(ARCHIVE_CRYPTO_SHA256_LIBC3)
static int __archive_libc3_sha256init(archive_sha256_ctx *ctx);
static int __archive_libc3_sha256update(archive_sha256_ctx *ctx, const void *indata, size_t insize);
static int __archive_libc3_sha256final(archive_sha256_ctx *ctx, void *md);
#elif defined(ARCHIVE_CRYPTO_SHA256_LIBMD)
static int __archive_libmd_sha256init(archive_sha256_ctx *ctx);
static int __archive_libmd_sha256update(archive_sha256_ctx *ctx, const void *indata, size_t insize);
static int __archive_libmd_sha256final(archive_sha256_ctx *ctx, void *md);
#elif defined(ARCHIVE_CRYPTO_SHA256_LIBSYSTEM)
static int __archive_libsystem_sha256init(archive_sha256_ctx *ctx);
static int __archive_libsystem_sha256update(archive_sha256_ctx *ctx, const void *indata, size_t insize);
static int __archive_libsystem_sha256final(archive_sha256_ctx *ctx, void *md);
#elif defined(ARCHIVE_CRYPTO_SHA256_MBEDTLS)
static int __archive_mbedtls_sha256init(archive_sha256_ctx *ctx);
static int __archive_mbedtls_sha256update(archive_sha256_ctx *ctx, const void *indata, size_t insize);
static int __archive_mbedtls_sha256final(archive_sha256_ctx *ctx, void *md);
#elif defined(ARCHIVE_CRYPTO_SHA256_NETTLE)
static int __archive_nettle_sha256init(archive_sha256_ctx *ctx);
static int __archive_nettle_sha256update(archive_sha256_ctx *ctx, const void *indata, size_t insize);
static int __archive_nettle_sha256final(archive_sha256_ctx *ctx, void *md);
#elif defined(ARCHIVE_CRYPTO_SHA256_OPENSSL)
static int __archive_openssl_sha256init(archive_sha256_ctx *ctx);
static int __archive_openssl_sha256update(archive_sha256_ctx *ctx, const void *indata, size_t insize);
static int __archive_openssl_sha256final(archive_sha256_ctx *ctx, void *md);
#elif defined(ARCHIVE_CRYPTO_SHA256_WIN)
static int __archive_windowsapi_sha256init(archive_sha256_ctx *ctx);
static int __archive_windowsapi_sha256update(archive_sha256_ctx *ctx, const void *indata, size_t insize);
static int __archive_windowsapi_sha256final(archive_sha256_ctx *ctx, void *md);
#else
static int __archive_stub_sha256init(archive_sha256_ctx *ctx);
static int __archive_stub_sha256update(archive_sha256_ctx *ctx, const void *indata, size_t insize);
static int __archive_stub_sha256final(archive_sha256_ctx *ctx, void *md);
#endif

/* SHA384 implementations */
#if defined(ARCHIVE_CRYPTO_SHA384_LIBC)
static int __archive_libc_sha384init(archive_sha384_ctx *ctx);
static int __archive_libc_sha384update(archive_sha384_ctx *ctx, const void *indata, size_t insize);
static int __archive_libc_sha384final(archive_sha384_ctx *ctx, void *md);
#elif defined(ARCHIVE_CRYPTO_SHA384_LIBC2)
static int __archive_libc2_sha384init(archive_sha384_ctx *ctx);
static int __archive_libc2_sha384update(archive_sha384_ctx *ctx, const void *indata, size_t insize);
static int __archive_libc2_sha384final(archive_sha384_ctx *ctx, void *md);
#elif defined(ARCHIVE_CRYPTO_SHA384_LIBC3)
static int __archive_libc3_sha384init(archive_sha384_ctx *ctx);
static int __archive_libc3_sha384update(archive_sha384_ctx *ctx, const void *indata, size_t insize);
static int __archive_libc3_sha384final(archive_sha384_ctx *ctx, void *md);
#elif defined(ARCHIVE_CRYPTO_SHA384_LIBSYSTEM)
static int __archive_libsystem_sha384init(archive_sha384_ctx *ctx);
static int __archive_libsystem_sha384update(archive_sha384_ctx *ctx, const void *indata, size_t insize);
static int __archive_libsystem_sha384final(archive_sha384_ctx *ctx, void *md);
#elif defined(ARCHIVE_CRYPTO_SHA384_MBEDTLS)
static int __archive_mbedtls_sha384init(archive_sha384_ctx *ctx);
static int __archive_mbedtls_sha384update(archive_sha384_ctx *ctx, const void *indata, size_t insize);
static int __archive_mbedtls_sha384final(archive_sha384_ctx *ctx, void *md);
#elif defined(ARCHIVE_CRYPTO_SHA384_NETTLE)
static int __archive_nettle_sha384init(archive_sha384_ctx *ctx);
static int __archive_nettle_sha384update(archive_sha384_ctx *ctx, const void *indata, size_t insize);
static int __archive_nettle_sha384final(archive_sha384_ctx *ctx, void *md);
#elif defined(ARCHIVE_CRYPTO_SHA384_OPENSSL)
static int __archive_openssl_sha384init(archive_sha384_ctx *ctx);
static int __archive_openssl_sha384update(archive_sha384_ctx *ctx, const void *indata, size_t insize);
static int __archive_openssl_sha384final(archive_sha384_ctx *ctx, void *md);
#elif defined(ARCHIVE_CRYPTO_SHA384_WIN)
static int __archive_windowsapi_sha384init(archive_sha384_ctx *ctx);
static int __archive_windowsapi_sha384update(archive_sha384_ctx *ctx, const void *indata, size_t insize);
static int __archive_windowsapi_sha384final(archive_sha384_ctx *ctx, void *md);
#else
static int __archive_stub_sha384init(archive_sha384_ctx *ctx);
static int __archive_stub_sha384update(archive_sha384_ctx *ctx, const void *indata, size_t insize);
static int __archive_stub_sha384final(archive_sha384_ctx *ctx, void *md);
#endif

/* SHA512 implementations */
#if defined(ARCHIVE_CRYPTO_SHA512_LIBC)
static int __archive_libc_sha512init(archive_sha512_ctx *ctx);
static int __archive_libc_sha512update(archive_sha512_ctx *ctx, const void *indata, size_t insize);
static int __archive_libc_sha512final(archive_sha512_ctx *ctx, void *md);
#elif defined(ARCHIVE_CRYPTO_SHA512_LIBC2)
static int __archive_libc2_sha512init(archive_sha512_ctx *ctx);
static int __archive_libc2_sha512update(archive_sha512_ctx *ctx, const void *indata, size_t insize);
static int __archive_libc2_sha512final(archive_sha512_ctx *ctx, void *md);
#elif defined(ARCHIVE_CRYPTO_SHA512_LIBC3)
static int __archive_libc3_sha512init(archive_sha512_ctx *ctx);
static int __archive_libc3_sha512update(archive_sha512_ctx *ctx, const void *indata, size_t insize);
static int __archive_libc3_sha512final(archive_sha512_ctx *ctx, void *md);
#elif defined(ARCHIVE_CRYPTO_SHA512_LIBMD)
static int __archive_libmd_sha512init(archive_sha512_ctx *ctx);
static int __archive_libmd_sha512update(archive_sha512_ctx *ctx, const void *indata, size_t insize);
static int __archive_libmd_sha512final(archive_sha512_ctx *ctx, void *md);
#elif defined(ARCHIVE_CRYPTO_SHA512_LIBSYSTEM)
static int __archive_libsystem_sha512init(archive_sha512_ctx *ctx);
static int __archive_libsystem_sha512update(archive_sha512_ctx *ctx, const void *indata, size_t insize);
static int __archive_libsystem_sha512final(archive_sha512_ctx *ctx, void *md);
#elif defined(ARCHIVE_CRYPTO_SHA512_MBEDTLS)
static int __archive_mbedtls_sha512init(archive_sha512_ctx *ctx);
static int __archive_mbedtls_sha512update(archive_sha512_ctx *ctx, const void *indata, size_t insize);
static int __archive_mbedtls_sha512final(archive_sha512_ctx *ctx, void *md);
#elif defined(ARCHIVE_CRYPTO_SHA512_NETTLE)
static int __archive_nettle_sha512init(archive_sha512_ctx *ctx);
static int __archive_nettle_sha512update(archive_sha512_ctx *ctx, const void *indata, size_t insize);
static int __archive_nettle_sha512final(archive_sha512_ctx *ctx, void *md);
#elif defined(ARCHIVE_CRYPTO_SHA512_OPENSSL)
static int __archive_openssl_sha512init(archive_sha512_ctx *ctx);
static int __archive_openssl_sha512update(archive_sha512_ctx *ctx, const void *indata, size_t insize);
static int __archive_openssl_sha512final(archive_sha512_ctx *ctx, void *md);
#elif defined(ARCHIVE_CRYPTO_SHA512_WIN)
static int __archive_windowsapi_sha512init(archive_sha512_ctx *ctx);
static int __archive_windowsapi_sha512update(archive_sha512_ctx *ctx, const void *indata, size_t insize);
static int __archive_windowsapi_sha512final(archive_sha512_ctx *ctx, void *md);
#else
static int __archive_stub_sha512init(archive_sha512_ctx *ctx);
static int __archive_stub_sha512update(archive_sha512_ctx *ctx, const void *indata, size_t insize);
static int __archive_stub_sha512final(archive_sha512_ctx *ctx, void *md);
#endif

/* NOTE: Message Digest functions are set based on availability and by the
 * following order of preference.
 * 1. libc
 * 2. libc2
 * 3. libc3
 * 4. libSystem
 * 5. Nettle
 * 6. OpenSSL
 * 7. libmd
 * 8. Windows API
 */
const struct archive_digest __archive_digest =
{
/* MD5 */
#if defined(ARCHIVE_CRYPTO_MD5_LIBC)
  &__archive_libc_md5init,
  &__archive_libc_md5update,
  &__archive_libc_md5final,
#elif defined(ARCHIVE_CRYPTO_MD5_LIBMD)
  &__archive_libmd_md5init,
  &__archive_libmd_md5update,
  &__archive_libmd_md5final,
#elif defined(ARCHIVE_CRYPTO_MD5_LIBSYSTEM)
  &__archive_libsystem_md5init,
  &__archive_libsystem_md5update,
  &__archive_libsystem_md5final,
#elif defined(ARCHIVE_CRYPTO_MD5_MBEDTLS)
  &__archive_mbedtls_md5init,
  &__archive_mbedtls_md5update,
  &__archive_mbedtls_md5final,
#elif defined(ARCHIVE_CRYPTO_MD5_NETTLE)
  &__archive_nettle_md5init,
  &__archive_nettle_md5update,
  &__archive_nettle_md5final,
#elif defined(ARCHIVE_CRYPTO_MD5_OPENSSL)
  &__archive_openssl_md5init,
  &__archive_openssl_md5update,
  &__archive_openssl_md5final,
#elif defined(ARCHIVE_CRYPTO_MD5_WIN)
  &__archive_windowsapi_md5init,
  &__archive_windowsapi_md5update,
  &__archive_windowsapi_md5final,
#else //if !defined(ARCHIVE_MD5_COMPILE_TEST)
  &__archive_stub_md5init,
  &__archive_stub_md5update,
  &__archive_stub_md5final,
#endif

/* RIPEMD160 */
#if defined(ARCHIVE_CRYPTO_RMD160_LIBC)
  &__archive_libc_ripemd160init,
  &__archive_libc_ripemd160update,
  &__archive_libc_ripemd160final,
#elif defined(ARCHIVE_CRYPTO_RMD160_LIBMD)
  &__archive_libmd_ripemd160init,
  &__archive_libmd_ripemd160update,
  &__archive_libmd_ripemd160final,
#elif defined(ARCHIVE_CRYPTO_RMD160_MBEDTLS)
  &__archive_mbedtls_ripemd160init,
  &__archive_mbedtls_ripemd160update,
  &__archive_mbedtls_ripemd160final,
#elif defined(ARCHIVE_CRYPTO_RMD160_NETTLE)
  &__archive_nettle_ripemd160init,
  &__archive_nettle_ripemd160update,
  &__archive_nettle_ripemd160final,
#elif defined(ARCHIVE_CRYPTO_RMD160_OPENSSL)
  &__archive_openssl_ripemd160init,
  &__archive_openssl_ripemd160update,
  &__archive_openssl_ripemd160final,
#else //if !defined(ARCHIVE_RMD160_COMPILE_TEST)
  &__archive_stub_ripemd160init,
  &__archive_stub_ripemd160update,
  &__archive_stub_ripemd160final,
#endif

/* SHA1 */
#if defined(ARCHIVE_CRYPTO_SHA1_LIBC)
  &__archive_libc_sha1init,
  &__archive_libc_sha1update,
  &__archive_libc_sha1final,
#elif defined(ARCHIVE_CRYPTO_SHA1_LIBMD)
  &__archive_libmd_sha1init,
  &__archive_libmd_sha1update,
  &__archive_libmd_sha1final,
#elif defined(ARCHIVE_CRYPTO_SHA1_LIBSYSTEM)
  &__archive_libsystem_sha1init,
  &__archive_libsystem_sha1update,
  &__archive_libsystem_sha1final,
#elif defined(ARCHIVE_CRYPTO_SHA1_MBEDTLS)
  &__archive_mbedtls_sha1init,
  &__archive_mbedtls_sha1update,
  &__archive_mbedtls_sha1final,
#elif defined(ARCHIVE_CRYPTO_SHA1_NETTLE)
  &__archive_nettle_sha1init,
  &__archive_nettle_sha1update,
  &__archive_nettle_sha1final,
#elif defined(ARCHIVE_CRYPTO_SHA1_OPENSSL)
  &__archive_openssl_sha1init,
  &__archive_openssl_sha1update,
  &__archive_openssl_sha1final,
#elif defined(ARCHIVE_CRYPTO_SHA1_WIN)
  &__archive_windowsapi_sha1init,
  &__archive_windowsapi_sha1update,
  &__archive_windowsapi_sha1final,
#else //if !defined(ARCHIVE_SHA1_COMPILE_TEST)
  &__archive_stub_sha1init,
  &__archive_stub_sha1update,
  &__archive_stub_sha1final,
#endif

/* SHA256 */
#if defined(ARCHIVE_CRYPTO_SHA256_LIBC)
  &__archive_libc_sha256init,
  &__archive_libc_sha256update,
  &__archive_libc_sha256final,
#elif defined(ARCHIVE_CRYPTO_SHA256_LIBC2)
  &__archive_libc2_sha256init,
  &__archive_libc2_sha256update,
  &__archive_libc2_sha256final,
#elif defined(ARCHIVE_CRYPTO_SHA256_LIBC3)
  &__archive_libc3_sha256init,
  &__archive_libc3_sha256update,
  &__archive_libc3_sha256final,
#elif defined(ARCHIVE_CRYPTO_SHA256_LIBMD)
  &__archive_libmd_sha256init,
  &__archive_libmd_sha256update,
  &__archive_libmd_sha256final,
#elif defined(ARCHIVE_CRYPTO_SHA256_LIBSYSTEM)
  &__archive_libsystem_sha256init,
  &__archive_libsystem_sha256update,
  &__archive_libsystem_sha256final,
#elif defined(ARCHIVE_CRYPTO_SHA256_MBEDTLS)
  &__archive_mbedtls_sha256init,
  &__archive_mbedtls_sha256update,
  &__archive_mbedtls_sha256final,
#elif defined(ARCHIVE_CRYPTO_SHA256_NETTLE)
  &__archive_nettle_sha256init,
  &__archive_nettle_sha256update,
  &__archive_nettle_sha256final,
#elif defined(ARCHIVE_CRYPTO_SHA256_OPENSSL)
  &__archive_openssl_sha256init,
  &__archive_openssl_sha256update,
  &__archive_openssl_sha256final,
#elif defined(ARCHIVE_CRYPTO_SHA256_WIN)
  &__archive_windowsapi_sha256init,
  &__archive_windowsapi_sha256update,
  &__archive_windowsapi_sha256final,
#else //if !defined(ARCHIVE_SHA256_COMPILE_TEST)
  &__archive_stub_sha256init,
  &__archive_stub_sha256update,
  &__archive_stub_sha256final,
#endif

/* SHA384 */
#if defined(ARCHIVE_CRYPTO_SHA384_LIBC)
  &__archive_libc_sha384init,
  &__archive_libc_sha384update,
  &__archive_libc_sha384final,
#elif defined(ARCHIVE_CRYPTO_SHA384_LIBC2)
  &__archive_libc2_sha384init,
  &__archive_libc2_sha384update,
  &__archive_libc2_sha384final,
#elif defined(ARCHIVE_CRYPTO_SHA384_LIBC3)
  &__archive_libc3_sha384init,
  &__archive_libc3_sha384update,
  &__archive_libc3_sha384final,
#elif defined(ARCHIVE_CRYPTO_SHA384_LIBSYSTEM)
  &__archive_libsystem_sha384init,
  &__archive_libsystem_sha384update,
  &__archive_libsystem_sha384final,
#elif defined(ARCHIVE_CRYPTO_SHA384_MBEDTLS)
  &__archive_mbedtls_sha384init,
  &__archive_mbedtls_sha384update,
  &__archive_mbedtls_sha384final,
#elif defined(ARCHIVE_CRYPTO_SHA384_NETTLE)
  &__archive_nettle_sha384init,
  &__archive_nettle_sha384update,
  &__archive_nettle_sha384final,
#elif defined(ARCHIVE_CRYPTO_SHA384_OPENSSL)
  &__archive_openssl_sha384init,
  &__archive_openssl_sha384update,
  &__archive_openssl_sha384final,
#elif defined(ARCHIVE_CRYPTO_SHA384_WIN)
  &__archive_windowsapi_sha384init,
  &__archive_windowsapi_sha384update,
  &__archive_windowsapi_sha384final,
#else //if !defined(ARCHIVE_SHA384_COMPILE_TEST)
  &__archive_stub_sha384init,
  &__archive_stub_sha384update,
  &__archive_stub_sha384final,
#endif

/* SHA512 */
#if defined(ARCHIVE_CRYPTO_SHA512_LIBC)
  &__archive_libc_sha512init,
  &__archive_libc_sha512update,
  &__archive_libc_sha512final
#elif defined(ARCHIVE_CRYPTO_SHA512_LIBC2)
  &__archive_libc2_sha512init,
  &__archive_libc2_sha512update,
  &__archive_libc2_sha512final
#elif defined(ARCHIVE_CRYPTO_SHA512_LIBC3)
  &__archive_libc3_sha512init,
  &__archive_libc3_sha512update,
  &__archive_libc3_sha512final
#elif defined(ARCHIVE_CRYPTO_SHA512_LIBMD)
  &__archive_libmd_sha512init,
  &__archive_libmd_sha512update,
  &__archive_libmd_sha512final
#elif defined(ARCHIVE_CRYPTO_SHA512_LIBSYSTEM)
  &__archive_libsystem_sha512init,
  &__archive_libsystem_sha512update,
  &__archive_libsystem_sha512final
#elif defined(ARCHIVE_CRYPTO_SHA512_MBEDTLS)
  &__archive_mbedtls_sha512init,
  &__archive_mbedtls_sha512update,
  &__archive_mbedtls_sha512final
#elif defined(ARCHIVE_CRYPTO_SHA512_NETTLE)
  &__archive_nettle_sha512init,
  &__archive_nettle_sha512update,
  &__archive_nettle_sha512final
#elif defined(ARCHIVE_CRYPTO_SHA512_OPENSSL)
  &__archive_openssl_sha512init,
  &__archive_openssl_sha512update,
  &__archive_openssl_sha512final
#elif defined(ARCHIVE_CRYPTO_SHA512_WIN)
  &__archive_windowsapi_sha512init,
  &__archive_windowsapi_sha512update,
  &__archive_windowsapi_sha512final
#else //if !defined(ARCHIVE_SHA512_COMPILE_TEST)
  &__archive_stub_sha512init,
  &__archive_stub_sha512update,
  &__archive_stub_sha512final
#endif
};
