module test120;

import config;
import cppconvhelpers;

struct git_revwalk {
	/+ unsigned walking:1,
			first_parent: 1,
			did_hide: 1,
			did_push: 1; +/
	ubyte bitfieldData_walking;
	final uint walking() const
	{
    	return (bitfieldData_walking >> 0) & 0x1;
	}
	final uint walking(uint value)
	{
    	bitfieldData_walking = (bitfieldData_walking & ~0x1) | ((value & 0x1) << 0);
    	return value;
	}
final uint first_parent() const
{
    return (bitfieldData_walking >> 1) & 0x1;
}
final uint first_parent(uint value)
{
    bitfieldData_walking = (bitfieldData_walking & ~0x2) | ((value & 0x1) << 1);
    return value;
}
final uint did_hide() const
{
    return (bitfieldData_walking >> 2) & 0x1;
}
final uint did_hide(uint value)
{
    bitfieldData_walking = (bitfieldData_walking & ~0x4) | ((value & 0x1) << 2);
    return value;
}
final uint did_push() const
{
    return (bitfieldData_walking >> 3) & 0x1;
}
final uint did_push(uint value)
{
    bitfieldData_walking = (bitfieldData_walking & ~0x8) | ((value & 0x1) << 3);
    return value;
}

}

void git_revwalk_reset(git_revwalk* walk)
{
	walk.first_parent = 0;
	walk.walking = 0;
	walk.did_push = walk.did_hide = 0;
}

