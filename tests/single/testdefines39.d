// https://yarchive.net/comp/linux/bad_macros.html
// https://docs.microsoft.com/en-us/windows-hardware/drivers/ddi/content/wdm/nf-wdm-removeheadlist
// https://docs.microsoft.com/en-us/windows/win32/api/ntdef/ns-ntdef-list_entry
module testdefines39;

import config;
import cppconvhelpers;

struct _LIST_ENTRY {
  _LIST_ENTRY* Flink;
  _LIST_ENTRY* Blink;
}
alias LIST_ENTRY = _LIST_ENTRY/+ , +/;
alias PLIST_ENTRY = _LIST_ENTRY */+ , +/;
alias PRLIST_ENTRY = _LIST_ENTRY;

/+ #define RemoveHeadList(ListHead) \
	(ListHead)->Flink;\
	{RemoveEntryList((ListHead)->Flink);}

#define BOOLEAN bool +/

/+ BOOLEAN +/bool RemoveEntryList(
  PLIST_ENTRY Entry
);

int main()
{
	LIST_ENTRY* l;
	LIST_ENTRY* x = /+ RemoveHeadList(l) +/(l).Flink;{RemoveEntryList((l).Flink);}
	return 0;
}

