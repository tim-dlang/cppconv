
module test111;

import config;
import cppconvhelpers;

alias git_refname_t = char[1024];

int reference_normalize_for_repo ( char* out_ , const(char)* name );

void git_reference_lookup_resolved ( const(char)* name )
{
	git_refname_t scan_name;

	reference_normalize_for_repo ( scan_name.ptr , name );
}

