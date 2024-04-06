module test161;

import config;
import cppconvhelpers;

alias dev_t = int;

alias pack_t = dev_t function(int, ulong/+[0]+/*  , const(char)** );

pack_t	pack_find(const(char)* );
__gshared pack_t	 pack_native;

