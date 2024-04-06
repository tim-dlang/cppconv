
typedef char git_refname_t[1024];

int reference_normalize_for_repo ( git_refname_t out_ , const char* name );

void git_reference_lookup_resolved ( const char* name )
{
	git_refname_t scan_name;

	reference_normalize_for_repo ( scan_name , name );
}
