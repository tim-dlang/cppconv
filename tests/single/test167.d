module test167;

import config;
import cppconvhelpers;

alias uint8_t = ubyte;
alias uint32_t = ulong;
struct blake2s_param__
{
uint8_t  depth;         /* 4 */
uint32_t leaf_length;   /* 8 */
uint8_t[5]  salt; /* 24 */
}

alias blake2s_param = blake2s_param__;

int blake2s_init_param( const(blake2s_param)* P );

void store32(uint32_t* );

void* memset ( void* __s , int __c , size_t __n );

int blake2sp_init_root(  )
{
  blake2s_param[1] P;
  P[0].depth = 2;
  store32( &P[0].leaf_length );
  memset( P[0].salt.ptr, 0, ( P[0].salt ). sizeof );
  return blake2s_init_param( P.ptr );
}

