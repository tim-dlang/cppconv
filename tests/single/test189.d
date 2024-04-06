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
module test189;

import config;
import cppconvhelpers;


alias archive_md5_ctx = ubyte;
alias archive_rmd160_ctx = ubyte;
alias archive_sha1_ctx = ubyte;
alias archive_sha256_ctx = ubyte;
alias archive_sha384_ctx = ubyte;
alias archive_sha512_ctx = ubyte;

/* Minimal interface to digest functionality for internal use in libarchive */
struct archive_digest
{
  /* Message Digest */
  int function(archive_md5_ctx* ctx) md5init;
  int function(archive_md5_ctx* , const(void)* , size_t) md5update;
  int function(archive_md5_ctx* , void* ) md5final;
  int function(archive_rmd160_ctx* ) rmd160init;
  int function(archive_rmd160_ctx* , const(void)* , size_t) rmd160update;
  int function(archive_rmd160_ctx* , void* ) rmd160final;
  int function(archive_sha1_ctx* ) sha1init;
  int function(archive_sha1_ctx* , const(void)* , size_t) sha1update;
  int function(archive_sha1_ctx* , void* ) sha1final;
  int function(archive_sha256_ctx* ) sha256init;
  int function(archive_sha256_ctx* , const(void)* , size_t) sha256update;
  int function(archive_sha256_ctx* , void* ) sha256final;
  int function(archive_sha384_ctx* ) sha384init;
  int function(archive_sha384_ctx* , const(void)* , size_t) sha384update;
  int function(archive_sha384_ctx* , void* ) sha384final;
  int function(archive_sha512_ctx* ) sha512init;
  int function(archive_sha512_ctx* , const(void)* , size_t) sha512update;
  int function(archive_sha512_ctx* , void* ) sha512final;
}

/+ extern const struct archive_digest __archive_digest; +/

/* MD5 implementations */
static if (defined!"ARCHIVE_CRYPTO_MD5_LIBC")
{
int __archive_libc_md5init(archive_md5_ctx* ctx);
int __archive_libc_md5update(archive_md5_ctx* ctx, const(void)* indata, size_t insize);
int __archive_libc_md5final(archive_md5_ctx* ctx, void* md);
}
static if (!defined!"ARCHIVE_CRYPTO_MD5_LIBC" && defined!"ARCHIVE_CRYPTO_MD5_LIBMD")
{
int __archive_libmd_md5init(archive_md5_ctx* ctx);
int __archive_libmd_md5update(archive_md5_ctx* ctx, const(void)* indata, size_t insize);
int __archive_libmd_md5final(archive_md5_ctx* ctx, void* md);
}
static if (!defined!"ARCHIVE_CRYPTO_MD5_LIBC" && !defined!"ARCHIVE_CRYPTO_MD5_LIBMD" && defined!"ARCHIVE_CRYPTO_MD5_LIBSYSTEM")
{
int __archive_libsystem_md5init(archive_md5_ctx* ctx);
int __archive_libsystem_md5update(archive_md5_ctx* ctx, const(void)* indata, size_t insize);
int __archive_libsystem_md5final(archive_md5_ctx* ctx, void* md);
}
static if (!defined!"ARCHIVE_CRYPTO_MD5_LIBC" && !defined!"ARCHIVE_CRYPTO_MD5_LIBMD" && !defined!"ARCHIVE_CRYPTO_MD5_LIBSYSTEM" && defined!"ARCHIVE_CRYPTO_MD5_MBEDTLS")
{
int __archive_mbedtls_md5init(archive_md5_ctx* ctx);
int __archive_mbedtls_md5update(archive_md5_ctx* ctx, const(void)* indata, size_t insize);
int __archive_mbedtls_md5final(archive_md5_ctx* ctx, void* md);
}
static if (!defined!"ARCHIVE_CRYPTO_MD5_LIBC" && !defined!"ARCHIVE_CRYPTO_MD5_LIBMD" && !defined!"ARCHIVE_CRYPTO_MD5_LIBSYSTEM" && !defined!"ARCHIVE_CRYPTO_MD5_MBEDTLS" && defined!"ARCHIVE_CRYPTO_MD5_NETTLE")
{
int __archive_nettle_md5init(archive_md5_ctx* ctx);
int __archive_nettle_md5update(archive_md5_ctx* ctx, const(void)* indata, size_t insize);
int __archive_nettle_md5final(archive_md5_ctx* ctx, void* md);
}
static if (!defined!"ARCHIVE_CRYPTO_MD5_LIBC" && !defined!"ARCHIVE_CRYPTO_MD5_LIBMD" && !defined!"ARCHIVE_CRYPTO_MD5_LIBSYSTEM" && !defined!"ARCHIVE_CRYPTO_MD5_MBEDTLS" && !defined!"ARCHIVE_CRYPTO_MD5_NETTLE" && defined!"ARCHIVE_CRYPTO_MD5_OPENSSL")
{
int __archive_openssl_md5init(archive_md5_ctx* ctx);
int __archive_openssl_md5update(archive_md5_ctx* ctx, const(void)* indata, size_t insize);
int __archive_openssl_md5final(archive_md5_ctx* ctx, void* md);
}
static if (!defined!"ARCHIVE_CRYPTO_MD5_LIBC" && !defined!"ARCHIVE_CRYPTO_MD5_LIBMD" && !defined!"ARCHIVE_CRYPTO_MD5_LIBSYSTEM" && !defined!"ARCHIVE_CRYPTO_MD5_MBEDTLS" && !defined!"ARCHIVE_CRYPTO_MD5_NETTLE" && !defined!"ARCHIVE_CRYPTO_MD5_OPENSSL" && defined!"ARCHIVE_CRYPTO_MD5_WIN")
{
int __archive_windowsapi_md5init(archive_md5_ctx* ctx);
int __archive_windowsapi_md5update(archive_md5_ctx* ctx, const(void)* indata, size_t insize);
int __archive_windowsapi_md5final(archive_md5_ctx* ctx, void* md);
}
static if (!defined!"ARCHIVE_CRYPTO_MD5_LIBC" && !defined!"ARCHIVE_CRYPTO_MD5_LIBMD" && !defined!"ARCHIVE_CRYPTO_MD5_LIBSYSTEM" && !defined!"ARCHIVE_CRYPTO_MD5_MBEDTLS" && !defined!"ARCHIVE_CRYPTO_MD5_NETTLE" && !defined!"ARCHIVE_CRYPTO_MD5_OPENSSL" && !defined!"ARCHIVE_CRYPTO_MD5_WIN")
{
int __archive_stub_md5init(archive_md5_ctx* ctx);
int __archive_stub_md5update(archive_md5_ctx* ctx, const(void)* indata, size_t insize);
int __archive_stub_md5final(archive_md5_ctx* ctx, void* md);
}

/* RIPEMD160 implementations */
static if (defined!"ARCHIVE_CRYPTO_RMD160_LIBC")
{
int __archive_libc_ripemd160init(archive_rmd160_ctx* ctx);
int __archive_libc_ripemd160update(archive_rmd160_ctx* ctx, const(void)* indata, size_t insize);
int __archive_libc_ripemd160final(archive_rmd160_ctx* ctx, void* md);
}
static if (!defined!"ARCHIVE_CRYPTO_RMD160_LIBC" && defined!"ARCHIVE_CRYPTO_RMD160_LIBMD")
{
int __archive_libmd_ripemd160init(archive_rmd160_ctx* ctx);
int __archive_libmd_ripemd160update(archive_rmd160_ctx* ctx, const(void)* indata, size_t insize);
int __archive_libmd_ripemd160final(archive_rmd160_ctx* ctx, void* md);
}
static if (!defined!"ARCHIVE_CRYPTO_RMD160_LIBC" && !defined!"ARCHIVE_CRYPTO_RMD160_LIBMD" && defined!"ARCHIVE_CRYPTO_RMD160_MBEDTLS")
{
int __archive_mbedtls_ripemd160init(archive_rmd160_ctx* ctx);
int
__archive_mbedtls_ripemd160update(archive_rmd160_ctx* ctx, const(void)* indata, size_t insize);
int __archive_mbedtls_ripemd160final(archive_rmd160_ctx* ctx, void* md);
}
static if (!defined!"ARCHIVE_CRYPTO_RMD160_LIBC" && !defined!"ARCHIVE_CRYPTO_RMD160_LIBMD" && !defined!"ARCHIVE_CRYPTO_RMD160_MBEDTLS" && defined!"ARCHIVE_CRYPTO_RMD160_NETTLE")
{
int __archive_nettle_ripemd160init(archive_rmd160_ctx* ctx);
int __archive_nettle_ripemd160update(archive_rmd160_ctx* ctx, const(void)* indata, size_t insize);
int __archive_nettle_ripemd160final(archive_rmd160_ctx* ctx, void* md);
}
static if (!defined!"ARCHIVE_CRYPTO_RMD160_LIBC" && !defined!"ARCHIVE_CRYPTO_RMD160_LIBMD" && !defined!"ARCHIVE_CRYPTO_RMD160_MBEDTLS" && !defined!"ARCHIVE_CRYPTO_RMD160_NETTLE" && defined!"ARCHIVE_CRYPTO_RMD160_OPENSSL")
{
int __archive_openssl_ripemd160init(archive_rmd160_ctx* ctx);
int __archive_openssl_ripemd160update(archive_rmd160_ctx* ctx, const(void)* indata, size_t insize);
int __archive_openssl_ripemd160final(archive_rmd160_ctx* ctx, void* md);
}
static if (!defined!"ARCHIVE_CRYPTO_RMD160_LIBC" && !defined!"ARCHIVE_CRYPTO_RMD160_LIBMD" && !defined!"ARCHIVE_CRYPTO_RMD160_MBEDTLS" && !defined!"ARCHIVE_CRYPTO_RMD160_NETTLE" && !defined!"ARCHIVE_CRYPTO_RMD160_OPENSSL")
{
int __archive_stub_ripemd160init(archive_rmd160_ctx* ctx);
int __archive_stub_ripemd160update(archive_rmd160_ctx* ctx, const(void)* indata, size_t insize);
int __archive_stub_ripemd160final(archive_rmd160_ctx* ctx, void* md);
}

/* SHA1 implementations */
static if (defined!"ARCHIVE_CRYPTO_SHA1_LIBC")
{
int __archive_libc_sha1init(archive_sha1_ctx* ctx);
int __archive_libc_sha1update(archive_sha1_ctx* ctx, const(void)* indata, size_t insize);
int __archive_libc_sha1final(archive_sha1_ctx* ctx, void* md);
}
static if (!defined!"ARCHIVE_CRYPTO_SHA1_LIBC" && defined!"ARCHIVE_CRYPTO_SHA1_LIBMD")
{
int __archive_libmd_sha1init(archive_sha1_ctx* ctx);
int __archive_libmd_sha1update(archive_sha1_ctx* ctx, const(void)* indata, size_t insize);
int __archive_libmd_sha1final(archive_sha1_ctx* ctx, void* md);
}
static if (!defined!"ARCHIVE_CRYPTO_SHA1_LIBC" && !defined!"ARCHIVE_CRYPTO_SHA1_LIBMD" && defined!"ARCHIVE_CRYPTO_SHA1_LIBSYSTEM")
{
int __archive_libsystem_sha1init(archive_sha1_ctx* ctx);
int __archive_libsystem_sha1update(archive_sha1_ctx* ctx, const(void)* indata, size_t insize);
int __archive_libsystem_sha1final(archive_sha1_ctx* ctx, void* md);
}
static if (!defined!"ARCHIVE_CRYPTO_SHA1_LIBC" && !defined!"ARCHIVE_CRYPTO_SHA1_LIBMD" && !defined!"ARCHIVE_CRYPTO_SHA1_LIBSYSTEM" && defined!"ARCHIVE_CRYPTO_SHA1_MBEDTLS")
{
int __archive_mbedtls_sha1init(archive_sha1_ctx* ctx);
int __archive_mbedtls_sha1update(archive_sha1_ctx* ctx, const(void)* indata, size_t insize);
int __archive_mbedtls_sha1final(archive_sha1_ctx* ctx, void* md);
}
static if (!defined!"ARCHIVE_CRYPTO_SHA1_LIBC" && !defined!"ARCHIVE_CRYPTO_SHA1_LIBMD" && !defined!"ARCHIVE_CRYPTO_SHA1_LIBSYSTEM" && !defined!"ARCHIVE_CRYPTO_SHA1_MBEDTLS" && defined!"ARCHIVE_CRYPTO_SHA1_NETTLE")
{
int __archive_nettle_sha1init(archive_sha1_ctx* ctx);
int __archive_nettle_sha1update(archive_sha1_ctx* ctx, const(void)* indata, size_t insize);
int __archive_nettle_sha1final(archive_sha1_ctx* ctx, void* md);
}
static if (!defined!"ARCHIVE_CRYPTO_SHA1_LIBC" && !defined!"ARCHIVE_CRYPTO_SHA1_LIBMD" && !defined!"ARCHIVE_CRYPTO_SHA1_LIBSYSTEM" && !defined!"ARCHIVE_CRYPTO_SHA1_MBEDTLS" && !defined!"ARCHIVE_CRYPTO_SHA1_NETTLE" && defined!"ARCHIVE_CRYPTO_SHA1_OPENSSL")
{
int __archive_openssl_sha1init(archive_sha1_ctx* ctx);
int __archive_openssl_sha1update(archive_sha1_ctx* ctx, const(void)* indata, size_t insize);
int __archive_openssl_sha1final(archive_sha1_ctx* ctx, void* md);
}
static if (!defined!"ARCHIVE_CRYPTO_SHA1_LIBC" && !defined!"ARCHIVE_CRYPTO_SHA1_LIBMD" && !defined!"ARCHIVE_CRYPTO_SHA1_LIBSYSTEM" && !defined!"ARCHIVE_CRYPTO_SHA1_MBEDTLS" && !defined!"ARCHIVE_CRYPTO_SHA1_NETTLE" && !defined!"ARCHIVE_CRYPTO_SHA1_OPENSSL" && defined!"ARCHIVE_CRYPTO_SHA1_WIN")
{
int __archive_windowsapi_sha1init(archive_sha1_ctx* ctx);
int __archive_windowsapi_sha1update(archive_sha1_ctx* ctx, const(void)* indata, size_t insize);
int __archive_windowsapi_sha1final(archive_sha1_ctx* ctx, void* md);
}
static if (!defined!"ARCHIVE_CRYPTO_SHA1_LIBC" && !defined!"ARCHIVE_CRYPTO_SHA1_LIBMD" && !defined!"ARCHIVE_CRYPTO_SHA1_LIBSYSTEM" && !defined!"ARCHIVE_CRYPTO_SHA1_MBEDTLS" && !defined!"ARCHIVE_CRYPTO_SHA1_NETTLE" && !defined!"ARCHIVE_CRYPTO_SHA1_OPENSSL" && !defined!"ARCHIVE_CRYPTO_SHA1_WIN")
{
int __archive_stub_sha1init(archive_sha1_ctx* ctx);
int __archive_stub_sha1update(archive_sha1_ctx* ctx, const(void)* indata, size_t insize);
int __archive_stub_sha1final(archive_sha1_ctx* ctx, void* md);
}

/* SHA256 implementations */
static if (defined!"ARCHIVE_CRYPTO_SHA256_LIBC")
{
int __archive_libc_sha256init(archive_sha256_ctx* ctx);
int __archive_libc_sha256update(archive_sha256_ctx* ctx, const(void)* indata, size_t insize);
int __archive_libc_sha256final(archive_sha256_ctx* ctx, void* md);
}
static if (!defined!"ARCHIVE_CRYPTO_SHA256_LIBC" && defined!"ARCHIVE_CRYPTO_SHA256_LIBC2")
{
int __archive_libc2_sha256init(archive_sha256_ctx* ctx);
int __archive_libc2_sha256update(archive_sha256_ctx* ctx, const(void)* indata, size_t insize);
int __archive_libc2_sha256final(archive_sha256_ctx* ctx, void* md);
}
static if (!defined!"ARCHIVE_CRYPTO_SHA256_LIBC" && !defined!"ARCHIVE_CRYPTO_SHA256_LIBC2" && defined!"ARCHIVE_CRYPTO_SHA256_LIBC3")
{
int __archive_libc3_sha256init(archive_sha256_ctx* ctx);
int __archive_libc3_sha256update(archive_sha256_ctx* ctx, const(void)* indata, size_t insize);
int __archive_libc3_sha256final(archive_sha256_ctx* ctx, void* md);
}
static if (!defined!"ARCHIVE_CRYPTO_SHA256_LIBC" && !defined!"ARCHIVE_CRYPTO_SHA256_LIBC2" && !defined!"ARCHIVE_CRYPTO_SHA256_LIBC3" && defined!"ARCHIVE_CRYPTO_SHA256_LIBMD")
{
int __archive_libmd_sha256init(archive_sha256_ctx* ctx);
int __archive_libmd_sha256update(archive_sha256_ctx* ctx, const(void)* indata, size_t insize);
int __archive_libmd_sha256final(archive_sha256_ctx* ctx, void* md);
}
static if (!defined!"ARCHIVE_CRYPTO_SHA256_LIBC" && !defined!"ARCHIVE_CRYPTO_SHA256_LIBC2" && !defined!"ARCHIVE_CRYPTO_SHA256_LIBC3" && !defined!"ARCHIVE_CRYPTO_SHA256_LIBMD" && defined!"ARCHIVE_CRYPTO_SHA256_LIBSYSTEM")
{
int __archive_libsystem_sha256init(archive_sha256_ctx* ctx);
int __archive_libsystem_sha256update(archive_sha256_ctx* ctx, const(void)* indata, size_t insize);
int __archive_libsystem_sha256final(archive_sha256_ctx* ctx, void* md);
}
static if (!defined!"ARCHIVE_CRYPTO_SHA256_LIBC" && !defined!"ARCHIVE_CRYPTO_SHA256_LIBC2" && !defined!"ARCHIVE_CRYPTO_SHA256_LIBC3" && !defined!"ARCHIVE_CRYPTO_SHA256_LIBMD" && !defined!"ARCHIVE_CRYPTO_SHA256_LIBSYSTEM" && defined!"ARCHIVE_CRYPTO_SHA256_MBEDTLS")
{
int __archive_mbedtls_sha256init(archive_sha256_ctx* ctx);
int __archive_mbedtls_sha256update(archive_sha256_ctx* ctx, const(void)* indata, size_t insize);
int __archive_mbedtls_sha256final(archive_sha256_ctx* ctx, void* md);
}
static if (!defined!"ARCHIVE_CRYPTO_SHA256_LIBC" && !defined!"ARCHIVE_CRYPTO_SHA256_LIBC2" && !defined!"ARCHIVE_CRYPTO_SHA256_LIBC3" && !defined!"ARCHIVE_CRYPTO_SHA256_LIBMD" && !defined!"ARCHIVE_CRYPTO_SHA256_LIBSYSTEM" && !defined!"ARCHIVE_CRYPTO_SHA256_MBEDTLS" && defined!"ARCHIVE_CRYPTO_SHA256_NETTLE")
{
int __archive_nettle_sha256init(archive_sha256_ctx* ctx);
int __archive_nettle_sha256update(archive_sha256_ctx* ctx, const(void)* indata, size_t insize);
int __archive_nettle_sha256final(archive_sha256_ctx* ctx, void* md);
}
static if (!defined!"ARCHIVE_CRYPTO_SHA256_LIBC" && !defined!"ARCHIVE_CRYPTO_SHA256_LIBC2" && !defined!"ARCHIVE_CRYPTO_SHA256_LIBC3" && !defined!"ARCHIVE_CRYPTO_SHA256_LIBMD" && !defined!"ARCHIVE_CRYPTO_SHA256_LIBSYSTEM" && !defined!"ARCHIVE_CRYPTO_SHA256_MBEDTLS" && !defined!"ARCHIVE_CRYPTO_SHA256_NETTLE" && defined!"ARCHIVE_CRYPTO_SHA256_OPENSSL")
{
int __archive_openssl_sha256init(archive_sha256_ctx* ctx);
int __archive_openssl_sha256update(archive_sha256_ctx* ctx, const(void)* indata, size_t insize);
int __archive_openssl_sha256final(archive_sha256_ctx* ctx, void* md);
}
static if (!defined!"ARCHIVE_CRYPTO_SHA256_LIBC" && !defined!"ARCHIVE_CRYPTO_SHA256_LIBC2" && !defined!"ARCHIVE_CRYPTO_SHA256_LIBC3" && !defined!"ARCHIVE_CRYPTO_SHA256_LIBMD" && !defined!"ARCHIVE_CRYPTO_SHA256_LIBSYSTEM" && !defined!"ARCHIVE_CRYPTO_SHA256_MBEDTLS" && !defined!"ARCHIVE_CRYPTO_SHA256_NETTLE" && !defined!"ARCHIVE_CRYPTO_SHA256_OPENSSL" && defined!"ARCHIVE_CRYPTO_SHA256_WIN")
{
int __archive_windowsapi_sha256init(archive_sha256_ctx* ctx);
int __archive_windowsapi_sha256update(archive_sha256_ctx* ctx, const(void)* indata, size_t insize);
int __archive_windowsapi_sha256final(archive_sha256_ctx* ctx, void* md);
}
static if (!defined!"ARCHIVE_CRYPTO_SHA256_LIBC" && !defined!"ARCHIVE_CRYPTO_SHA256_LIBC2" && !defined!"ARCHIVE_CRYPTO_SHA256_LIBC3" && !defined!"ARCHIVE_CRYPTO_SHA256_LIBMD" && !defined!"ARCHIVE_CRYPTO_SHA256_LIBSYSTEM" && !defined!"ARCHIVE_CRYPTO_SHA256_MBEDTLS" && !defined!"ARCHIVE_CRYPTO_SHA256_NETTLE" && !defined!"ARCHIVE_CRYPTO_SHA256_OPENSSL" && !defined!"ARCHIVE_CRYPTO_SHA256_WIN")
{
int __archive_stub_sha256init(archive_sha256_ctx* ctx);
int __archive_stub_sha256update(archive_sha256_ctx* ctx, const(void)* indata, size_t insize);
int __archive_stub_sha256final(archive_sha256_ctx* ctx, void* md);
}

/* SHA384 implementations */
static if (defined!"ARCHIVE_CRYPTO_SHA384_LIBC")
{
int __archive_libc_sha384init(archive_sha384_ctx* ctx);
int __archive_libc_sha384update(archive_sha384_ctx* ctx, const(void)* indata, size_t insize);
int __archive_libc_sha384final(archive_sha384_ctx* ctx, void* md);
}
static if (!defined!"ARCHIVE_CRYPTO_SHA384_LIBC" && defined!"ARCHIVE_CRYPTO_SHA384_LIBC2")
{
int __archive_libc2_sha384init(archive_sha384_ctx* ctx);
int __archive_libc2_sha384update(archive_sha384_ctx* ctx, const(void)* indata, size_t insize);
int __archive_libc2_sha384final(archive_sha384_ctx* ctx, void* md);
}
static if (!defined!"ARCHIVE_CRYPTO_SHA384_LIBC" && !defined!"ARCHIVE_CRYPTO_SHA384_LIBC2" && defined!"ARCHIVE_CRYPTO_SHA384_LIBC3")
{
int __archive_libc3_sha384init(archive_sha384_ctx* ctx);
int __archive_libc3_sha384update(archive_sha384_ctx* ctx, const(void)* indata, size_t insize);
int __archive_libc3_sha384final(archive_sha384_ctx* ctx, void* md);
}
static if (!defined!"ARCHIVE_CRYPTO_SHA384_LIBC" && !defined!"ARCHIVE_CRYPTO_SHA384_LIBC2" && !defined!"ARCHIVE_CRYPTO_SHA384_LIBC3" && defined!"ARCHIVE_CRYPTO_SHA384_LIBSYSTEM")
{
int __archive_libsystem_sha384init(archive_sha384_ctx* ctx);
int __archive_libsystem_sha384update(archive_sha384_ctx* ctx, const(void)* indata, size_t insize);
int __archive_libsystem_sha384final(archive_sha384_ctx* ctx, void* md);
}
static if (!defined!"ARCHIVE_CRYPTO_SHA384_LIBC" && !defined!"ARCHIVE_CRYPTO_SHA384_LIBC2" && !defined!"ARCHIVE_CRYPTO_SHA384_LIBC3" && !defined!"ARCHIVE_CRYPTO_SHA384_LIBSYSTEM" && defined!"ARCHIVE_CRYPTO_SHA384_MBEDTLS")
{
int __archive_mbedtls_sha384init(archive_sha384_ctx* ctx);
int __archive_mbedtls_sha384update(archive_sha384_ctx* ctx, const(void)* indata, size_t insize);
int __archive_mbedtls_sha384final(archive_sha384_ctx* ctx, void* md);
}
static if (!defined!"ARCHIVE_CRYPTO_SHA384_LIBC" && !defined!"ARCHIVE_CRYPTO_SHA384_LIBC2" && !defined!"ARCHIVE_CRYPTO_SHA384_LIBC3" && !defined!"ARCHIVE_CRYPTO_SHA384_LIBSYSTEM" && !defined!"ARCHIVE_CRYPTO_SHA384_MBEDTLS" && defined!"ARCHIVE_CRYPTO_SHA384_NETTLE")
{
int __archive_nettle_sha384init(archive_sha384_ctx* ctx);
int __archive_nettle_sha384update(archive_sha384_ctx* ctx, const(void)* indata, size_t insize);
int __archive_nettle_sha384final(archive_sha384_ctx* ctx, void* md);
}
static if (!defined!"ARCHIVE_CRYPTO_SHA384_LIBC" && !defined!"ARCHIVE_CRYPTO_SHA384_LIBC2" && !defined!"ARCHIVE_CRYPTO_SHA384_LIBC3" && !defined!"ARCHIVE_CRYPTO_SHA384_LIBSYSTEM" && !defined!"ARCHIVE_CRYPTO_SHA384_MBEDTLS" && !defined!"ARCHIVE_CRYPTO_SHA384_NETTLE" && defined!"ARCHIVE_CRYPTO_SHA384_OPENSSL")
{
int __archive_openssl_sha384init(archive_sha384_ctx* ctx);
int __archive_openssl_sha384update(archive_sha384_ctx* ctx, const(void)* indata, size_t insize);
int __archive_openssl_sha384final(archive_sha384_ctx* ctx, void* md);
}
static if (!defined!"ARCHIVE_CRYPTO_SHA384_LIBC" && !defined!"ARCHIVE_CRYPTO_SHA384_LIBC2" && !defined!"ARCHIVE_CRYPTO_SHA384_LIBC3" && !defined!"ARCHIVE_CRYPTO_SHA384_LIBSYSTEM" && !defined!"ARCHIVE_CRYPTO_SHA384_MBEDTLS" && !defined!"ARCHIVE_CRYPTO_SHA384_NETTLE" && !defined!"ARCHIVE_CRYPTO_SHA384_OPENSSL" && defined!"ARCHIVE_CRYPTO_SHA384_WIN")
{
int __archive_windowsapi_sha384init(archive_sha384_ctx* ctx);
int __archive_windowsapi_sha384update(archive_sha384_ctx* ctx, const(void)* indata, size_t insize);
int __archive_windowsapi_sha384final(archive_sha384_ctx* ctx, void* md);
}
static if (!defined!"ARCHIVE_CRYPTO_SHA384_LIBC" && !defined!"ARCHIVE_CRYPTO_SHA384_LIBC2" && !defined!"ARCHIVE_CRYPTO_SHA384_LIBC3" && !defined!"ARCHIVE_CRYPTO_SHA384_LIBSYSTEM" && !defined!"ARCHIVE_CRYPTO_SHA384_MBEDTLS" && !defined!"ARCHIVE_CRYPTO_SHA384_NETTLE" && !defined!"ARCHIVE_CRYPTO_SHA384_OPENSSL" && !defined!"ARCHIVE_CRYPTO_SHA384_WIN")
{
int __archive_stub_sha384init(archive_sha384_ctx* ctx);
int __archive_stub_sha384update(archive_sha384_ctx* ctx, const(void)* indata, size_t insize);
int __archive_stub_sha384final(archive_sha384_ctx* ctx, void* md);
}

/* SHA512 implementations */
static if (defined!"ARCHIVE_CRYPTO_SHA512_LIBC")
{
int __archive_libc_sha512init(archive_sha512_ctx* ctx);
int __archive_libc_sha512update(archive_sha512_ctx* ctx, const(void)* indata, size_t insize);
int __archive_libc_sha512final(archive_sha512_ctx* ctx, void* md);
}
static if (!defined!"ARCHIVE_CRYPTO_SHA512_LIBC" && defined!"ARCHIVE_CRYPTO_SHA512_LIBC2")
{
int __archive_libc2_sha512init(archive_sha512_ctx* ctx);
int __archive_libc2_sha512update(archive_sha512_ctx* ctx, const(void)* indata, size_t insize);
int __archive_libc2_sha512final(archive_sha512_ctx* ctx, void* md);
}
static if (!defined!"ARCHIVE_CRYPTO_SHA512_LIBC" && !defined!"ARCHIVE_CRYPTO_SHA512_LIBC2" && defined!"ARCHIVE_CRYPTO_SHA512_LIBC3")
{
int __archive_libc3_sha512init(archive_sha512_ctx* ctx);
int __archive_libc3_sha512update(archive_sha512_ctx* ctx, const(void)* indata, size_t insize);
int __archive_libc3_sha512final(archive_sha512_ctx* ctx, void* md);
}
static if (!defined!"ARCHIVE_CRYPTO_SHA512_LIBC" && !defined!"ARCHIVE_CRYPTO_SHA512_LIBC2" && !defined!"ARCHIVE_CRYPTO_SHA512_LIBC3" && defined!"ARCHIVE_CRYPTO_SHA512_LIBMD")
{
int __archive_libmd_sha512init(archive_sha512_ctx* ctx);
int __archive_libmd_sha512update(archive_sha512_ctx* ctx, const(void)* indata, size_t insize);
int __archive_libmd_sha512final(archive_sha512_ctx* ctx, void* md);
}
static if (!defined!"ARCHIVE_CRYPTO_SHA512_LIBC" && !defined!"ARCHIVE_CRYPTO_SHA512_LIBC2" && !defined!"ARCHIVE_CRYPTO_SHA512_LIBC3" && !defined!"ARCHIVE_CRYPTO_SHA512_LIBMD" && defined!"ARCHIVE_CRYPTO_SHA512_LIBSYSTEM")
{
int __archive_libsystem_sha512init(archive_sha512_ctx* ctx);
int __archive_libsystem_sha512update(archive_sha512_ctx* ctx, const(void)* indata, size_t insize);
int __archive_libsystem_sha512final(archive_sha512_ctx* ctx, void* md);
}
static if (!defined!"ARCHIVE_CRYPTO_SHA512_LIBC" && !defined!"ARCHIVE_CRYPTO_SHA512_LIBC2" && !defined!"ARCHIVE_CRYPTO_SHA512_LIBC3" && !defined!"ARCHIVE_CRYPTO_SHA512_LIBMD" && !defined!"ARCHIVE_CRYPTO_SHA512_LIBSYSTEM" && defined!"ARCHIVE_CRYPTO_SHA512_MBEDTLS")
{
int __archive_mbedtls_sha512init(archive_sha512_ctx* ctx);
int __archive_mbedtls_sha512update(archive_sha512_ctx* ctx, const(void)* indata, size_t insize);
int __archive_mbedtls_sha512final(archive_sha512_ctx* ctx, void* md);
}
static if (!defined!"ARCHIVE_CRYPTO_SHA512_LIBC" && !defined!"ARCHIVE_CRYPTO_SHA512_LIBC2" && !defined!"ARCHIVE_CRYPTO_SHA512_LIBC3" && !defined!"ARCHIVE_CRYPTO_SHA512_LIBMD" && !defined!"ARCHIVE_CRYPTO_SHA512_LIBSYSTEM" && !defined!"ARCHIVE_CRYPTO_SHA512_MBEDTLS" && defined!"ARCHIVE_CRYPTO_SHA512_NETTLE")
{
int __archive_nettle_sha512init(archive_sha512_ctx* ctx);
int __archive_nettle_sha512update(archive_sha512_ctx* ctx, const(void)* indata, size_t insize);
int __archive_nettle_sha512final(archive_sha512_ctx* ctx, void* md);
}
static if (!defined!"ARCHIVE_CRYPTO_SHA512_LIBC" && !defined!"ARCHIVE_CRYPTO_SHA512_LIBC2" && !defined!"ARCHIVE_CRYPTO_SHA512_LIBC3" && !defined!"ARCHIVE_CRYPTO_SHA512_LIBMD" && !defined!"ARCHIVE_CRYPTO_SHA512_LIBSYSTEM" && !defined!"ARCHIVE_CRYPTO_SHA512_MBEDTLS" && !defined!"ARCHIVE_CRYPTO_SHA512_NETTLE" && defined!"ARCHIVE_CRYPTO_SHA512_OPENSSL")
{
int __archive_openssl_sha512init(archive_sha512_ctx* ctx);
int __archive_openssl_sha512update(archive_sha512_ctx* ctx, const(void)* indata, size_t insize);
int __archive_openssl_sha512final(archive_sha512_ctx* ctx, void* md);
}
static if (!defined!"ARCHIVE_CRYPTO_SHA512_LIBC" && !defined!"ARCHIVE_CRYPTO_SHA512_LIBC2" && !defined!"ARCHIVE_CRYPTO_SHA512_LIBC3" && !defined!"ARCHIVE_CRYPTO_SHA512_LIBMD" && !defined!"ARCHIVE_CRYPTO_SHA512_LIBSYSTEM" && !defined!"ARCHIVE_CRYPTO_SHA512_MBEDTLS" && !defined!"ARCHIVE_CRYPTO_SHA512_NETTLE" && !defined!"ARCHIVE_CRYPTO_SHA512_OPENSSL" && defined!"ARCHIVE_CRYPTO_SHA512_WIN")
{
int __archive_windowsapi_sha512init(archive_sha512_ctx* ctx);
int __archive_windowsapi_sha512update(archive_sha512_ctx* ctx, const(void)* indata, size_t insize);
int __archive_windowsapi_sha512final(archive_sha512_ctx* ctx, void* md);
}
static if (!defined!"ARCHIVE_CRYPTO_SHA512_LIBC" && !defined!"ARCHIVE_CRYPTO_SHA512_LIBC2" && !defined!"ARCHIVE_CRYPTO_SHA512_LIBC3" && !defined!"ARCHIVE_CRYPTO_SHA512_LIBMD" && !defined!"ARCHIVE_CRYPTO_SHA512_LIBSYSTEM" && !defined!"ARCHIVE_CRYPTO_SHA512_MBEDTLS" && !defined!"ARCHIVE_CRYPTO_SHA512_NETTLE" && !defined!"ARCHIVE_CRYPTO_SHA512_OPENSSL" && !defined!"ARCHIVE_CRYPTO_SHA512_WIN")
{
int __archive_stub_sha512init(archive_sha512_ctx* ctx);
int __archive_stub_sha512update(archive_sha512_ctx* ctx, const(void)* indata, size_t insize);
int __archive_stub_sha512final(archive_sha512_ctx* ctx, void* md);
}

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
__gshared const(archive_digest) __archive_digest =
mixin("const(archive_digest)(" ~ q{
    }
    ~ (defined!"ARCHIVE_CRYPTO_MD5_LIBC" ? q{

        /* MD5 */
        /+ #if defined(ARCHIVE_CRYPTO_MD5_LIBC) +/
          &__archive_libc_md5init,
          &__archive_libc_md5update,
          &__archive_libc_md5final,
    }:"")
    ~ ((!defined!"ARCHIVE_CRYPTO_MD5_LIBC" && defined!"ARCHIVE_CRYPTO_MD5_LIBMD") ? q{
        /+ #elif defined(ARCHIVE_CRYPTO_MD5_LIBMD) +/
          &__archive_libmd_md5init,
          &__archive_libmd_md5update,
          &__archive_libmd_md5final,
    }:"")
    ~ ((!defined!"ARCHIVE_CRYPTO_MD5_LIBC" && !defined!"ARCHIVE_CRYPTO_MD5_LIBMD" && defined!"ARCHIVE_CRYPTO_MD5_LIBSYSTEM") ? q{
        /+ #elif defined(ARCHIVE_CRYPTO_MD5_LIBSYSTEM) +/
          &__archive_libsystem_md5init,
          &__archive_libsystem_md5update,
          &__archive_libsystem_md5final,
    }:"")
    ~ ((!defined!"ARCHIVE_CRYPTO_MD5_LIBC" && !defined!"ARCHIVE_CRYPTO_MD5_LIBMD" && !defined!"ARCHIVE_CRYPTO_MD5_LIBSYSTEM" && defined!"ARCHIVE_CRYPTO_MD5_MBEDTLS") ? q{
        /+ #elif defined(ARCHIVE_CRYPTO_MD5_MBEDTLS) +/
          &__archive_mbedtls_md5init,
          &__archive_mbedtls_md5update,
          &__archive_mbedtls_md5final,
    }:"")
    ~ ((!defined!"ARCHIVE_CRYPTO_MD5_LIBC" && !defined!"ARCHIVE_CRYPTO_MD5_LIBMD" && !defined!"ARCHIVE_CRYPTO_MD5_LIBSYSTEM" && !defined!"ARCHIVE_CRYPTO_MD5_MBEDTLS" && defined!"ARCHIVE_CRYPTO_MD5_NETTLE") ? q{
        /+ #elif defined(ARCHIVE_CRYPTO_MD5_NETTLE) +/
          &__archive_nettle_md5init,
          &__archive_nettle_md5update,
          &__archive_nettle_md5final,
    }:"")
    ~ ((!defined!"ARCHIVE_CRYPTO_MD5_LIBC" && !defined!"ARCHIVE_CRYPTO_MD5_LIBMD" && !defined!"ARCHIVE_CRYPTO_MD5_LIBSYSTEM" && !defined!"ARCHIVE_CRYPTO_MD5_MBEDTLS" && !defined!"ARCHIVE_CRYPTO_MD5_NETTLE" && defined!"ARCHIVE_CRYPTO_MD5_OPENSSL") ? q{
        /+ #elif defined(ARCHIVE_CRYPTO_MD5_OPENSSL) +/
          &__archive_openssl_md5init,
          &__archive_openssl_md5update,
          &__archive_openssl_md5final,
    }:"")
    ~ ((!defined!"ARCHIVE_CRYPTO_MD5_LIBC" && !defined!"ARCHIVE_CRYPTO_MD5_LIBMD" && !defined!"ARCHIVE_CRYPTO_MD5_LIBSYSTEM" && !defined!"ARCHIVE_CRYPTO_MD5_MBEDTLS" && !defined!"ARCHIVE_CRYPTO_MD5_NETTLE" && !defined!"ARCHIVE_CRYPTO_MD5_OPENSSL" && defined!"ARCHIVE_CRYPTO_MD5_WIN") ? q{
        /+ #elif defined(ARCHIVE_CRYPTO_MD5_WIN) +/
          &__archive_windowsapi_md5init,
          &__archive_windowsapi_md5update,
          &__archive_windowsapi_md5final,
    }:"")
    ~ ((!defined!"ARCHIVE_CRYPTO_MD5_LIBC" && !defined!"ARCHIVE_CRYPTO_MD5_LIBMD" && !defined!"ARCHIVE_CRYPTO_MD5_LIBSYSTEM" && !defined!"ARCHIVE_CRYPTO_MD5_MBEDTLS" && !defined!"ARCHIVE_CRYPTO_MD5_NETTLE" && !defined!"ARCHIVE_CRYPTO_MD5_OPENSSL" && !defined!"ARCHIVE_CRYPTO_MD5_WIN") ? q{
        /+ #else +/ //if !defined(ARCHIVE_MD5_COMPILE_TEST)
          &__archive_stub_md5init,
          &__archive_stub_md5update,
          &__archive_stub_md5final,
    }:"")
    ~ (defined!"ARCHIVE_CRYPTO_RMD160_LIBC" ? q{
        /+ #endif

        /* RIPEMD160 */
        #if defined(ARCHIVE_CRYPTO_RMD160_LIBC) +/
          &__archive_libc_ripemd160init,
          &__archive_libc_ripemd160update,
          &__archive_libc_ripemd160final,
    }:"")
    ~ ((!defined!"ARCHIVE_CRYPTO_RMD160_LIBC" && defined!"ARCHIVE_CRYPTO_RMD160_LIBMD") ? q{
        /+ #elif defined(ARCHIVE_CRYPTO_RMD160_LIBMD) +/
          &__archive_libmd_ripemd160init,
          &__archive_libmd_ripemd160update,
          &__archive_libmd_ripemd160final,
    }:"")
    ~ ((!defined!"ARCHIVE_CRYPTO_RMD160_LIBC" && !defined!"ARCHIVE_CRYPTO_RMD160_LIBMD" && defined!"ARCHIVE_CRYPTO_RMD160_MBEDTLS") ? q{
        /+ #elif defined(ARCHIVE_CRYPTO_RMD160_MBEDTLS) +/
          &__archive_mbedtls_ripemd160init,
          &__archive_mbedtls_ripemd160update,
          &__archive_mbedtls_ripemd160final,
    }:"")
    ~ ((!defined!"ARCHIVE_CRYPTO_RMD160_LIBC" && !defined!"ARCHIVE_CRYPTO_RMD160_LIBMD" && !defined!"ARCHIVE_CRYPTO_RMD160_MBEDTLS" && defined!"ARCHIVE_CRYPTO_RMD160_NETTLE") ? q{
        /+ #elif defined(ARCHIVE_CRYPTO_RMD160_NETTLE) +/
          &__archive_nettle_ripemd160init,
          &__archive_nettle_ripemd160update,
          &__archive_nettle_ripemd160final,
    }:"")
    ~ ((!defined!"ARCHIVE_CRYPTO_RMD160_LIBC" && !defined!"ARCHIVE_CRYPTO_RMD160_LIBMD" && !defined!"ARCHIVE_CRYPTO_RMD160_MBEDTLS" && !defined!"ARCHIVE_CRYPTO_RMD160_NETTLE" && defined!"ARCHIVE_CRYPTO_RMD160_OPENSSL") ? q{
        /+ #elif defined(ARCHIVE_CRYPTO_RMD160_OPENSSL) +/
          &__archive_openssl_ripemd160init,
          &__archive_openssl_ripemd160update,
          &__archive_openssl_ripemd160final,
    }:"")
    ~ ((!defined!"ARCHIVE_CRYPTO_RMD160_LIBC" && !defined!"ARCHIVE_CRYPTO_RMD160_LIBMD" && !defined!"ARCHIVE_CRYPTO_RMD160_MBEDTLS" && !defined!"ARCHIVE_CRYPTO_RMD160_NETTLE" && !defined!"ARCHIVE_CRYPTO_RMD160_OPENSSL") ? q{
        /+ #else +/ //if !defined(ARCHIVE_RMD160_COMPILE_TEST)
          &__archive_stub_ripemd160init,
          &__archive_stub_ripemd160update,
          &__archive_stub_ripemd160final,
    }:"")
    ~ (defined!"ARCHIVE_CRYPTO_SHA1_LIBC" ? q{
        /+ #endif

        /* SHA1 */
        #if defined(ARCHIVE_CRYPTO_SHA1_LIBC) +/
          &__archive_libc_sha1init,
          &__archive_libc_sha1update,
          &__archive_libc_sha1final,
    }:"")
    ~ ((!defined!"ARCHIVE_CRYPTO_SHA1_LIBC" && defined!"ARCHIVE_CRYPTO_SHA1_LIBMD") ? q{
        /+ #elif defined(ARCHIVE_CRYPTO_SHA1_LIBMD) +/
          &__archive_libmd_sha1init,
          &__archive_libmd_sha1update,
          &__archive_libmd_sha1final,
    }:"")
    ~ ((!defined!"ARCHIVE_CRYPTO_SHA1_LIBC" && !defined!"ARCHIVE_CRYPTO_SHA1_LIBMD" && defined!"ARCHIVE_CRYPTO_SHA1_LIBSYSTEM") ? q{
        /+ #elif defined(ARCHIVE_CRYPTO_SHA1_LIBSYSTEM) +/
          &__archive_libsystem_sha1init,
          &__archive_libsystem_sha1update,
          &__archive_libsystem_sha1final,
    }:"")
    ~ ((!defined!"ARCHIVE_CRYPTO_SHA1_LIBC" && !defined!"ARCHIVE_CRYPTO_SHA1_LIBMD" && !defined!"ARCHIVE_CRYPTO_SHA1_LIBSYSTEM" && defined!"ARCHIVE_CRYPTO_SHA1_MBEDTLS") ? q{
        /+ #elif defined(ARCHIVE_CRYPTO_SHA1_MBEDTLS) +/
          &__archive_mbedtls_sha1init,
          &__archive_mbedtls_sha1update,
          &__archive_mbedtls_sha1final,
    }:"")
    ~ ((!defined!"ARCHIVE_CRYPTO_SHA1_LIBC" && !defined!"ARCHIVE_CRYPTO_SHA1_LIBMD" && !defined!"ARCHIVE_CRYPTO_SHA1_LIBSYSTEM" && !defined!"ARCHIVE_CRYPTO_SHA1_MBEDTLS" && defined!"ARCHIVE_CRYPTO_SHA1_NETTLE") ? q{
        /+ #elif defined(ARCHIVE_CRYPTO_SHA1_NETTLE) +/
          &__archive_nettle_sha1init,
          &__archive_nettle_sha1update,
          &__archive_nettle_sha1final,
    }:"")
    ~ ((!defined!"ARCHIVE_CRYPTO_SHA1_LIBC" && !defined!"ARCHIVE_CRYPTO_SHA1_LIBMD" && !defined!"ARCHIVE_CRYPTO_SHA1_LIBSYSTEM" && !defined!"ARCHIVE_CRYPTO_SHA1_MBEDTLS" && !defined!"ARCHIVE_CRYPTO_SHA1_NETTLE" && defined!"ARCHIVE_CRYPTO_SHA1_OPENSSL") ? q{
        /+ #elif defined(ARCHIVE_CRYPTO_SHA1_OPENSSL) +/
          &__archive_openssl_sha1init,
          &__archive_openssl_sha1update,
          &__archive_openssl_sha1final,
    }:"")
    ~ ((!defined!"ARCHIVE_CRYPTO_SHA1_LIBC" && !defined!"ARCHIVE_CRYPTO_SHA1_LIBMD" && !defined!"ARCHIVE_CRYPTO_SHA1_LIBSYSTEM" && !defined!"ARCHIVE_CRYPTO_SHA1_MBEDTLS" && !defined!"ARCHIVE_CRYPTO_SHA1_NETTLE" && !defined!"ARCHIVE_CRYPTO_SHA1_OPENSSL" && defined!"ARCHIVE_CRYPTO_SHA1_WIN") ? q{
        /+ #elif defined(ARCHIVE_CRYPTO_SHA1_WIN) +/
          &__archive_windowsapi_sha1init,
          &__archive_windowsapi_sha1update,
          &__archive_windowsapi_sha1final,
    }:"")
    ~ ((!defined!"ARCHIVE_CRYPTO_SHA1_LIBC" && !defined!"ARCHIVE_CRYPTO_SHA1_LIBMD" && !defined!"ARCHIVE_CRYPTO_SHA1_LIBSYSTEM" && !defined!"ARCHIVE_CRYPTO_SHA1_MBEDTLS" && !defined!"ARCHIVE_CRYPTO_SHA1_NETTLE" && !defined!"ARCHIVE_CRYPTO_SHA1_OPENSSL" && !defined!"ARCHIVE_CRYPTO_SHA1_WIN") ? q{
        /+ #else +/ //if !defined(ARCHIVE_SHA1_COMPILE_TEST)
          &__archive_stub_sha1init,
          &__archive_stub_sha1update,
          &__archive_stub_sha1final,
    }:"")
    ~ (defined!"ARCHIVE_CRYPTO_SHA256_LIBC" ? q{
        /+ #endif

        /* SHA256 */
        #if defined(ARCHIVE_CRYPTO_SHA256_LIBC) +/
          &__archive_libc_sha256init,
          &__archive_libc_sha256update,
          &__archive_libc_sha256final,
    }:"")
    ~ ((!defined!"ARCHIVE_CRYPTO_SHA256_LIBC" && defined!"ARCHIVE_CRYPTO_SHA256_LIBC2") ? q{
        /+ #elif defined(ARCHIVE_CRYPTO_SHA256_LIBC2) +/
          &__archive_libc2_sha256init,
          &__archive_libc2_sha256update,
          &__archive_libc2_sha256final,
    }:"")
    ~ ((!defined!"ARCHIVE_CRYPTO_SHA256_LIBC" && !defined!"ARCHIVE_CRYPTO_SHA256_LIBC2" && defined!"ARCHIVE_CRYPTO_SHA256_LIBC3") ? q{
        /+ #elif defined(ARCHIVE_CRYPTO_SHA256_LIBC3) +/
          &__archive_libc3_sha256init,
          &__archive_libc3_sha256update,
          &__archive_libc3_sha256final,
    }:"")
    ~ ((!defined!"ARCHIVE_CRYPTO_SHA256_LIBC" && !defined!"ARCHIVE_CRYPTO_SHA256_LIBC2" && !defined!"ARCHIVE_CRYPTO_SHA256_LIBC3" && defined!"ARCHIVE_CRYPTO_SHA256_LIBMD") ? q{
        /+ #elif defined(ARCHIVE_CRYPTO_SHA256_LIBMD) +/
          &__archive_libmd_sha256init,
          &__archive_libmd_sha256update,
          &__archive_libmd_sha256final,
    }:"")
    ~ ((!defined!"ARCHIVE_CRYPTO_SHA256_LIBC" && !defined!"ARCHIVE_CRYPTO_SHA256_LIBC2" && !defined!"ARCHIVE_CRYPTO_SHA256_LIBC3" && !defined!"ARCHIVE_CRYPTO_SHA256_LIBMD" && defined!"ARCHIVE_CRYPTO_SHA256_LIBSYSTEM") ? q{
        /+ #elif defined(ARCHIVE_CRYPTO_SHA256_LIBSYSTEM) +/
          &__archive_libsystem_sha256init,
          &__archive_libsystem_sha256update,
          &__archive_libsystem_sha256final,
    }:"")
    ~ ((!defined!"ARCHIVE_CRYPTO_SHA256_LIBC" && !defined!"ARCHIVE_CRYPTO_SHA256_LIBC2" && !defined!"ARCHIVE_CRYPTO_SHA256_LIBC3" && !defined!"ARCHIVE_CRYPTO_SHA256_LIBMD" && !defined!"ARCHIVE_CRYPTO_SHA256_LIBSYSTEM" && defined!"ARCHIVE_CRYPTO_SHA256_MBEDTLS") ? q{
        /+ #elif defined(ARCHIVE_CRYPTO_SHA256_MBEDTLS) +/
          &__archive_mbedtls_sha256init,
          &__archive_mbedtls_sha256update,
          &__archive_mbedtls_sha256final,
    }:"")
    ~ ((!defined!"ARCHIVE_CRYPTO_SHA256_LIBC" && !defined!"ARCHIVE_CRYPTO_SHA256_LIBC2" && !defined!"ARCHIVE_CRYPTO_SHA256_LIBC3" && !defined!"ARCHIVE_CRYPTO_SHA256_LIBMD" && !defined!"ARCHIVE_CRYPTO_SHA256_LIBSYSTEM" && !defined!"ARCHIVE_CRYPTO_SHA256_MBEDTLS" && defined!"ARCHIVE_CRYPTO_SHA256_NETTLE") ? q{
        /+ #elif defined(ARCHIVE_CRYPTO_SHA256_NETTLE) +/
          &__archive_nettle_sha256init,
          &__archive_nettle_sha256update,
          &__archive_nettle_sha256final,
    }:"")
    ~ ((!defined!"ARCHIVE_CRYPTO_SHA256_LIBC" && !defined!"ARCHIVE_CRYPTO_SHA256_LIBC2" && !defined!"ARCHIVE_CRYPTO_SHA256_LIBC3" && !defined!"ARCHIVE_CRYPTO_SHA256_LIBMD" && !defined!"ARCHIVE_CRYPTO_SHA256_LIBSYSTEM" && !defined!"ARCHIVE_CRYPTO_SHA256_MBEDTLS" && !defined!"ARCHIVE_CRYPTO_SHA256_NETTLE" && defined!"ARCHIVE_CRYPTO_SHA256_OPENSSL") ? q{
        /+ #elif defined(ARCHIVE_CRYPTO_SHA256_OPENSSL) +/
          &__archive_openssl_sha256init,
          &__archive_openssl_sha256update,
          &__archive_openssl_sha256final,
    }:"")
    ~ ((!defined!"ARCHIVE_CRYPTO_SHA256_LIBC" && !defined!"ARCHIVE_CRYPTO_SHA256_LIBC2" && !defined!"ARCHIVE_CRYPTO_SHA256_LIBC3" && !defined!"ARCHIVE_CRYPTO_SHA256_LIBMD" && !defined!"ARCHIVE_CRYPTO_SHA256_LIBSYSTEM" && !defined!"ARCHIVE_CRYPTO_SHA256_MBEDTLS" && !defined!"ARCHIVE_CRYPTO_SHA256_NETTLE" && !defined!"ARCHIVE_CRYPTO_SHA256_OPENSSL" && defined!"ARCHIVE_CRYPTO_SHA256_WIN") ? q{
        /+ #elif defined(ARCHIVE_CRYPTO_SHA256_WIN) +/
          &__archive_windowsapi_sha256init,
          &__archive_windowsapi_sha256update,
          &__archive_windowsapi_sha256final,
    }:"")
    ~ ((!defined!"ARCHIVE_CRYPTO_SHA256_LIBC" && !defined!"ARCHIVE_CRYPTO_SHA256_LIBC2" && !defined!"ARCHIVE_CRYPTO_SHA256_LIBC3" && !defined!"ARCHIVE_CRYPTO_SHA256_LIBMD" && !defined!"ARCHIVE_CRYPTO_SHA256_LIBSYSTEM" && !defined!"ARCHIVE_CRYPTO_SHA256_MBEDTLS" && !defined!"ARCHIVE_CRYPTO_SHA256_NETTLE" && !defined!"ARCHIVE_CRYPTO_SHA256_OPENSSL" && !defined!"ARCHIVE_CRYPTO_SHA256_WIN") ? q{
        /+ #else +/ //if !defined(ARCHIVE_SHA256_COMPILE_TEST)
          &__archive_stub_sha256init,
          &__archive_stub_sha256update,
          &__archive_stub_sha256final,
    }:"")
    ~ (defined!"ARCHIVE_CRYPTO_SHA384_LIBC" ? q{
        /+ #endif

        /* SHA384 */
        #if defined(ARCHIVE_CRYPTO_SHA384_LIBC) +/
          &__archive_libc_sha384init,
          &__archive_libc_sha384update,
          &__archive_libc_sha384final,
    }:"")
    ~ ((!defined!"ARCHIVE_CRYPTO_SHA384_LIBC" && defined!"ARCHIVE_CRYPTO_SHA384_LIBC2") ? q{
        /+ #elif defined(ARCHIVE_CRYPTO_SHA384_LIBC2) +/
          &__archive_libc2_sha384init,
          &__archive_libc2_sha384update,
          &__archive_libc2_sha384final,
    }:"")
    ~ ((!defined!"ARCHIVE_CRYPTO_SHA384_LIBC" && !defined!"ARCHIVE_CRYPTO_SHA384_LIBC2" && defined!"ARCHIVE_CRYPTO_SHA384_LIBC3") ? q{
        /+ #elif defined(ARCHIVE_CRYPTO_SHA384_LIBC3) +/
          &__archive_libc3_sha384init,
          &__archive_libc3_sha384update,
          &__archive_libc3_sha384final,
    }:"")
    ~ ((!defined!"ARCHIVE_CRYPTO_SHA384_LIBC" && !defined!"ARCHIVE_CRYPTO_SHA384_LIBC2" && !defined!"ARCHIVE_CRYPTO_SHA384_LIBC3" && defined!"ARCHIVE_CRYPTO_SHA384_LIBSYSTEM") ? q{
        /+ #elif defined(ARCHIVE_CRYPTO_SHA384_LIBSYSTEM) +/
          &__archive_libsystem_sha384init,
          &__archive_libsystem_sha384update,
          &__archive_libsystem_sha384final,
    }:"")
    ~ ((!defined!"ARCHIVE_CRYPTO_SHA384_LIBC" && !defined!"ARCHIVE_CRYPTO_SHA384_LIBC2" && !defined!"ARCHIVE_CRYPTO_SHA384_LIBC3" && !defined!"ARCHIVE_CRYPTO_SHA384_LIBSYSTEM" && defined!"ARCHIVE_CRYPTO_SHA384_MBEDTLS") ? q{
        /+ #elif defined(ARCHIVE_CRYPTO_SHA384_MBEDTLS) +/
          &__archive_mbedtls_sha384init,
          &__archive_mbedtls_sha384update,
          &__archive_mbedtls_sha384final,
    }:"")
    ~ ((!defined!"ARCHIVE_CRYPTO_SHA384_LIBC" && !defined!"ARCHIVE_CRYPTO_SHA384_LIBC2" && !defined!"ARCHIVE_CRYPTO_SHA384_LIBC3" && !defined!"ARCHIVE_CRYPTO_SHA384_LIBSYSTEM" && !defined!"ARCHIVE_CRYPTO_SHA384_MBEDTLS" && defined!"ARCHIVE_CRYPTO_SHA384_NETTLE") ? q{
        /+ #elif defined(ARCHIVE_CRYPTO_SHA384_NETTLE) +/
          &__archive_nettle_sha384init,
          &__archive_nettle_sha384update,
          &__archive_nettle_sha384final,
    }:"")
    ~ ((!defined!"ARCHIVE_CRYPTO_SHA384_LIBC" && !defined!"ARCHIVE_CRYPTO_SHA384_LIBC2" && !defined!"ARCHIVE_CRYPTO_SHA384_LIBC3" && !defined!"ARCHIVE_CRYPTO_SHA384_LIBSYSTEM" && !defined!"ARCHIVE_CRYPTO_SHA384_MBEDTLS" && !defined!"ARCHIVE_CRYPTO_SHA384_NETTLE" && defined!"ARCHIVE_CRYPTO_SHA384_OPENSSL") ? q{
        /+ #elif defined(ARCHIVE_CRYPTO_SHA384_OPENSSL) +/
          &__archive_openssl_sha384init,
          &__archive_openssl_sha384update,
          &__archive_openssl_sha384final,
    }:"")
    ~ ((!defined!"ARCHIVE_CRYPTO_SHA384_LIBC" && !defined!"ARCHIVE_CRYPTO_SHA384_LIBC2" && !defined!"ARCHIVE_CRYPTO_SHA384_LIBC3" && !defined!"ARCHIVE_CRYPTO_SHA384_LIBSYSTEM" && !defined!"ARCHIVE_CRYPTO_SHA384_MBEDTLS" && !defined!"ARCHIVE_CRYPTO_SHA384_NETTLE" && !defined!"ARCHIVE_CRYPTO_SHA384_OPENSSL" && defined!"ARCHIVE_CRYPTO_SHA384_WIN") ? q{
        /+ #elif defined(ARCHIVE_CRYPTO_SHA384_WIN) +/
          &__archive_windowsapi_sha384init,
          &__archive_windowsapi_sha384update,
          &__archive_windowsapi_sha384final,
    }:"")
    ~ ((!defined!"ARCHIVE_CRYPTO_SHA384_LIBC" && !defined!"ARCHIVE_CRYPTO_SHA384_LIBC2" && !defined!"ARCHIVE_CRYPTO_SHA384_LIBC3" && !defined!"ARCHIVE_CRYPTO_SHA384_LIBSYSTEM" && !defined!"ARCHIVE_CRYPTO_SHA384_MBEDTLS" && !defined!"ARCHIVE_CRYPTO_SHA384_NETTLE" && !defined!"ARCHIVE_CRYPTO_SHA384_OPENSSL" && !defined!"ARCHIVE_CRYPTO_SHA384_WIN") ? q{
        /+ #else +/ //if !defined(ARCHIVE_SHA384_COMPILE_TEST)
          &__archive_stub_sha384init,
          &__archive_stub_sha384update,
          &__archive_stub_sha384final,
    }:"")
    ~ (defined!"ARCHIVE_CRYPTO_SHA512_LIBC" ? q{
        /+ #endif

        /* SHA512 */
        #if defined(ARCHIVE_CRYPTO_SHA512_LIBC) +/
          &__archive_libc_sha512init,
          &__archive_libc_sha512update,
          &__archive_libc_sha512final
    }:"")
    ~ ((!defined!"ARCHIVE_CRYPTO_SHA512_LIBC" && defined!"ARCHIVE_CRYPTO_SHA512_LIBC2") ? q{
        /+ #elif defined(ARCHIVE_CRYPTO_SHA512_LIBC2) +/
          &__archive_libc2_sha512init,
          &__archive_libc2_sha512update,
          &__archive_libc2_sha512final
    }:"")
    ~ ((!defined!"ARCHIVE_CRYPTO_SHA512_LIBC" && !defined!"ARCHIVE_CRYPTO_SHA512_LIBC2" && defined!"ARCHIVE_CRYPTO_SHA512_LIBC3") ? q{
        /+ #elif defined(ARCHIVE_CRYPTO_SHA512_LIBC3) +/
          &__archive_libc3_sha512init,
          &__archive_libc3_sha512update,
          &__archive_libc3_sha512final
    }:"")
    ~ ((!defined!"ARCHIVE_CRYPTO_SHA512_LIBC" && !defined!"ARCHIVE_CRYPTO_SHA512_LIBC2" && !defined!"ARCHIVE_CRYPTO_SHA512_LIBC3" && defined!"ARCHIVE_CRYPTO_SHA512_LIBMD") ? q{
        /+ #elif defined(ARCHIVE_CRYPTO_SHA512_LIBMD) +/
          &__archive_libmd_sha512init,
          &__archive_libmd_sha512update,
          &__archive_libmd_sha512final
    }:"")
    ~ ((!defined!"ARCHIVE_CRYPTO_SHA512_LIBC" && !defined!"ARCHIVE_CRYPTO_SHA512_LIBC2" && !defined!"ARCHIVE_CRYPTO_SHA512_LIBC3" && !defined!"ARCHIVE_CRYPTO_SHA512_LIBMD" && defined!"ARCHIVE_CRYPTO_SHA512_LIBSYSTEM") ? q{
        /+ #elif defined(ARCHIVE_CRYPTO_SHA512_LIBSYSTEM) +/
          &__archive_libsystem_sha512init,
          &__archive_libsystem_sha512update,
          &__archive_libsystem_sha512final
    }:"")
    ~ ((!defined!"ARCHIVE_CRYPTO_SHA512_LIBC" && !defined!"ARCHIVE_CRYPTO_SHA512_LIBC2" && !defined!"ARCHIVE_CRYPTO_SHA512_LIBC3" && !defined!"ARCHIVE_CRYPTO_SHA512_LIBMD" && !defined!"ARCHIVE_CRYPTO_SHA512_LIBSYSTEM" && defined!"ARCHIVE_CRYPTO_SHA512_MBEDTLS") ? q{
        /+ #elif defined(ARCHIVE_CRYPTO_SHA512_MBEDTLS) +/
          &__archive_mbedtls_sha512init,
          &__archive_mbedtls_sha512update,
          &__archive_mbedtls_sha512final
    }:"")
    ~ ((!defined!"ARCHIVE_CRYPTO_SHA512_LIBC" && !defined!"ARCHIVE_CRYPTO_SHA512_LIBC2" && !defined!"ARCHIVE_CRYPTO_SHA512_LIBC3" && !defined!"ARCHIVE_CRYPTO_SHA512_LIBMD" && !defined!"ARCHIVE_CRYPTO_SHA512_LIBSYSTEM" && !defined!"ARCHIVE_CRYPTO_SHA512_MBEDTLS" && defined!"ARCHIVE_CRYPTO_SHA512_NETTLE") ? q{
        /+ #elif defined(ARCHIVE_CRYPTO_SHA512_NETTLE) +/
          &__archive_nettle_sha512init,
          &__archive_nettle_sha512update,
          &__archive_nettle_sha512final
    }:"")
    ~ ((!defined!"ARCHIVE_CRYPTO_SHA512_LIBC" && !defined!"ARCHIVE_CRYPTO_SHA512_LIBC2" && !defined!"ARCHIVE_CRYPTO_SHA512_LIBC3" && !defined!"ARCHIVE_CRYPTO_SHA512_LIBMD" && !defined!"ARCHIVE_CRYPTO_SHA512_LIBSYSTEM" && !defined!"ARCHIVE_CRYPTO_SHA512_MBEDTLS" && !defined!"ARCHIVE_CRYPTO_SHA512_NETTLE" && defined!"ARCHIVE_CRYPTO_SHA512_OPENSSL") ? q{
        /+ #elif defined(ARCHIVE_CRYPTO_SHA512_OPENSSL) +/
          &__archive_openssl_sha512init,
          &__archive_openssl_sha512update,
          &__archive_openssl_sha512final
    }:"")
    ~ ((!defined!"ARCHIVE_CRYPTO_SHA512_LIBC" && !defined!"ARCHIVE_CRYPTO_SHA512_LIBC2" && !defined!"ARCHIVE_CRYPTO_SHA512_LIBC3" && !defined!"ARCHIVE_CRYPTO_SHA512_LIBMD" && !defined!"ARCHIVE_CRYPTO_SHA512_LIBSYSTEM" && !defined!"ARCHIVE_CRYPTO_SHA512_MBEDTLS" && !defined!"ARCHIVE_CRYPTO_SHA512_NETTLE" && !defined!"ARCHIVE_CRYPTO_SHA512_OPENSSL" && defined!"ARCHIVE_CRYPTO_SHA512_WIN") ? q{
        /+ #elif defined(ARCHIVE_CRYPTO_SHA512_WIN) +/
          &__archive_windowsapi_sha512init,
          &__archive_windowsapi_sha512update,
          &__archive_windowsapi_sha512final
    }:"")
    ~ ((!defined!"ARCHIVE_CRYPTO_SHA512_LIBC" && !defined!"ARCHIVE_CRYPTO_SHA512_LIBC2" && !defined!"ARCHIVE_CRYPTO_SHA512_LIBC3" && !defined!"ARCHIVE_CRYPTO_SHA512_LIBMD" && !defined!"ARCHIVE_CRYPTO_SHA512_LIBSYSTEM" && !defined!"ARCHIVE_CRYPTO_SHA512_MBEDTLS" && !defined!"ARCHIVE_CRYPTO_SHA512_NETTLE" && !defined!"ARCHIVE_CRYPTO_SHA512_OPENSSL" && !defined!"ARCHIVE_CRYPTO_SHA512_WIN") ? q{
        /+ #else +/ //if !defined(ARCHIVE_SHA512_COMPILE_TEST)
          &__archive_stub_sha512init,
          &__archive_stub_sha512update,
          &__archive_stub_sha512final
}:"")
 ~ ")")/+ #endif +/
;

