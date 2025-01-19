module test86;

import config;
import cppconvhelpers;

/+ extern "C"
{ +/
struct S
{
	int test1;

	/+ unsigned test2: 1; +/
	static if (defined!"DEF")
	{
	ubyte bitfieldData_test2;
	uint test2() const
	{
    	return (bitfieldData_test2 >> 0) & 0x1;
	}
	uint test2(uint value)
	{
    	bitfieldData_test2 = (bitfieldData_test2 & ~0x1) | ((value & 0x1) << 0);
    	return value;
	}
	}
	static if (!defined!"DEF")
	{
	ubyte bitfieldData_test2;
	uint test2() const
	{
    	return (bitfieldData_test2 >> 0) & 0x1;
	}
	uint test2(uint value)
	{
    	bitfieldData_test2 = (bitfieldData_test2 & ~0x1) | ((value & 0x1) << 0);
    	return value;
	}
	}
	/+ unsigned test3: 2; +/
	static if (defined!"DEF")
	{
	uint test3() const
	{
    	return (bitfieldData_test2 >> 1) & 0x3;
	}
	uint test3(uint value)
	{
    	bitfieldData_test2 = (bitfieldData_test2 & ~0x6) | ((value & 0x3) << 1);
    	return value;
	}
	}
	static if (!defined!"DEF")
	{
	uint test3() const
	{
    	return (bitfieldData_test2 >> 1) & 0x3;
	}
	uint test3(uint value)
	{
    	bitfieldData_test2 = (bitfieldData_test2 & ~0x6) | ((value & 0x3) << 1);
    	return value;
	}
	}
	static if (!defined!"DEF")
	{
    	uint test4;
	}
	/+ unsigned test5: 1; +/
	static if (defined!"DEF")
	{
	uint test5() const
	{
    	return (bitfieldData_test2 >> 3) & 0x1;
	}
	uint test5(uint value)
	{
    	bitfieldData_test2 = (bitfieldData_test2 & ~0x8) | ((value & 0x1) << 3);
    	return value;
	}
	}
	static if (!defined!"DEF")
	{
	ubyte bitfieldData_test5;
	uint test5() const
	{
    	return (bitfieldData_test5 >> 0) & 0x1;
	}
	uint test5(uint value)
	{
    	bitfieldData_test5 = (bitfieldData_test5 & ~0x1) | ((value & 0x1) << 0);
    	return value;
	}
	}
}

union U
{
	S s;
	ubyte[S.sizeof]  data;
}

int printf ( const(char)*  format, ... );
/+ }

#define TEST(name) \
	{ \
		U u; \
		 \
		for(unsigned i=0; i<sizeof(S); i++) \
			u.data[i] = 0; \
		 \
		u.s.name = 1; \
		 \
		printf(#name); \
		for(unsigned i=0; i<sizeof(S); i++) \
			printf(" %02X", u.data[i]); \
		printf("\n"); \
	} +/

int main()
{
	/+ TEST(test1) +/
{U u;for(uint i=0;i<S.sizeof;i++)u.data[i]=0;u.s.test1=1;printf("test1");for(uint i=0;i<S.sizeof;i++)printf(" %02X",u.data[i]);printf("\n");}	/+ TEST(test2) +/
{U u;for(uint i=0;i<S.sizeof;i++)u.data[i]=0;u.s.test2=1;printf("test2");for(uint i=0;i<S.sizeof;i++)printf(" %02X",u.data[i]);printf("\n");}	/+ TEST(test3) +/
{U u;for(uint i=0;i<S.sizeof;i++)u.data[i]=0;u.s.test3=1;printf("test3");for(uint i=0;i<S.sizeof;i++)printf(" %02X",u.data[i]);printf("\n");}static if (!defined!"DEF")
	{
    	/+ TEST(test4) +/
    {U u;for(uint i=0;i<S.sizeof;i++)u.data[i]=0;u.s.test4=1;printf("test4");for(uint i=0;i<S.sizeof;i++)printf(" %02X",u.data[i]);printf("\n");}
	}
	/+ TEST(test5) +/
{U u;for(uint i=0;i<S.sizeof;i++)u.data[i]=0;u.s.test5=1;printf("test5");for(uint i=0;i<S.sizeof;i++)printf(" %02X",u.data[i]);printf("\n");}
	return 0;
}

