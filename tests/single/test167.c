typedef unsigned char uint8_t;
typedef unsigned long uint32_t;
typedef unsigned long size_t;
struct blake2s_param__
{
uint8_t  depth;         /* 4 */
uint32_t leaf_length;   /* 8 */
uint8_t  salt[5]; /* 24 */
};

typedef struct blake2s_param__ blake2s_param;

int blake2s_init_param( const blake2s_param *P );

void store32(uint32_t *);

void* memset ( void* __s , int __c , size_t __n );

static int blake2sp_init_root( void )
{
  blake2s_param P[1];
  P->depth = 2;
  store32( &P->leaf_length );
  memset( P->salt, 0, sizeof( P->salt ) );
  return blake2s_init_param( P );
}
