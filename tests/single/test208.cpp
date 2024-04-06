struct QListData {
    struct NotIndirectLayout {};
    struct ArrayCompatibleLayout   : NotIndirectLayout {};
};
