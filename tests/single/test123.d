
module test123;

import config;
import cppconvhelpers;

struct write_data {
}

void write_on_section(
	void* data)
{
	.write_data* write_data__1 = cast(.write_data*)data;
}

void write_on_variable(
	void* data)
{
	.write_data* write_data__1 = cast(.write_data*)data;
}

