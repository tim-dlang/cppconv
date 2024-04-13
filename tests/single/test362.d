module test362;

import config;
import cppconvhelpers;

class Parent
{
public:
    /+ virtual +/ void f(int) {}
    final void f(double) {}
}

class Child : Parent
{
public:
    override void f(int) {}
    final void f(float) {}
}

class Child2 : Child
{
public:
    override void f(int) {}
}

