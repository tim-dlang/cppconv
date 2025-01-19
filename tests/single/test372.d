module test372;

import config;
import cppconvhelpers;

enum E
{
    a /+ __attribute__ ((__deprecated__("text"))) +/ = 1,
    b = 3
}

