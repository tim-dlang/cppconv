module test191;

import config;
import cppconvhelpers;

static if (defined!"BYFOUR")
{
/+ #  define TBLS 8 +/
enum TBLS = 8;
}
static if (!defined!"BYFOUR")
{
/+ #  define TBLS 1 +/
enum TBLS = 1;
}

/* crc32.h -- tables for rapid CRC calculation
 * Generated automatically by crc32.c
 */

__gshared const(ulong)[5][ (mixin((defined!"BYFOUR") ? q{
        TBLS
    } : q{
        TBLS
    }))]  crc_table =
mixin("mixin(buildStaticArray!(q{const(ulong)[5]}, (mixin((defined!\"BYFOUR\") ? q{
        TBLS
    } : q{
        TBLS
    })), q{" ~ q{
    }
    ~ (defined!"BYFOUR" ? q{

          [
            0x00000000UL, 0x77073096UL, 0xee0e612cUL, 0x990951baUL, 0x076dc419UL]
        /+ #ifdef BYFOUR +/
          ,
          [
            0x00000000UL, 0x191b3141UL, 0x32366282UL, 0x2b2d53c3UL, 0x646cc504UL]
          ,
          [
            0x00000000UL, 0x01c26a37UL, 0x0384d46eUL, 0x0246be59UL, 0x0709a8dcUL]
          ,
          [
            0x00000000UL, 0xb8bc6765UL, 0xaa09c88bUL, 0x12b5afeeUL, 0x8f629757UL]
          ,
          [
            0x00000000UL, 0x96300777UL, 0x2c610eeeUL, 0xba510999UL, 0x19c46d07UL]
          ,
          [
            0x00000000UL, 0x41311b19UL, 0x82623632UL, 0xc3532d2bUL, 0x04c56c64UL]
          ,
          [
            0x00000000UL, 0x376ac201UL, 0x6ed48403UL, 0x59be4602UL, 0xdca80907UL]
          ,
          [
            0x00000000UL, 0x6567bcb8UL, 0x8bc809aaUL, 0xeeafb512UL, 0x5797628fUL]
        /+ #endif +/
          
    }:"")
    ~ (!defined!"BYFOUR" ? q{
        [0x00000000UL,0x77073096UL,0xee0e612cUL,0x990951baUL,0x076dc419UL]
}:"")
 ~ "}))");

