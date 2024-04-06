// https://yarchive.net/comp/linux/bad_macros.html
// https://docs.microsoft.com/en-us/windows-hardware/drivers/ddi/content/wdm/nf-wdm-removeheadlist
// https://docs.microsoft.com/en-us/windows/win32/api/ntdef/ns-ntdef-list_entry
typedef struct _LIST_ENTRY {
  struct _LIST_ENTRY *Flink;
  struct _LIST_ENTRY *Blink;
} LIST_ENTRY, *PLIST_ENTRY, PRLIST_ENTRY;

#define RemoveHeadList(ListHead) \
	(ListHead)->Flink;\
	{RemoveEntryList((ListHead)->Flink);}

#define BOOLEAN bool

BOOLEAN RemoveEntryList(
  PLIST_ENTRY Entry
);

int main()
{
	LIST_ENTRY *l;
	LIST_ENTRY *x = RemoveHeadList(l);
	return 0;
}
