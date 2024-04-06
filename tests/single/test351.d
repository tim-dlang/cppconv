
module test351;

import config;
import cppconvhelpers;

/*1a*/ 
/*1b*/ __gshared const(uint) /*1c*/  /*1d*/ i1 /*1e*/ = /*1f*/ 1;

/*2a*/ 
/*2b*/ __gshared const(Identity!(mixin((defined!"DEF")?q{const(uint)}:q{const(ulong)}))) /*2c*/
/+ #ifdef DEF +/
/*2d*/  /*2e*/
/+ #endif
/*2f*/
#ifndef DEF +/
/*2g*/  /*2h*/
/+ #endif +/
/*2i*/ i2 /*2j*/ = /*2k*/ 2;

/*3a*/ 
/*3b*/ __gshared const(const(ulong)) /*3c*/
/+ #ifdef DEF +/
/*3d*/  /*3e*/
/+ #endif +/
/*3f*/  /*3g*/ i3 /*3h*/ = /*3i*/ 3;

/*4a*/ 
/*4b*/ __gshared const(const(ulong)) /*4c*/  /*4d*/
/+ #ifdef DEF +/
/*4e*/  /*4f*/
/+ #endif +/
/*4g*/ i4 /*4h*/ = /*4i*/ 4;

/*5a*/
/+ #ifdef DEF +/
static if (defined!"DEF")
{
/*5b*/ 
}
__gshared long /*5c*/
/+ #endif +/
/*5d*/  /*5e*/ i5 /*5f*/ = /*5g*/ 5;

