module test208;

import config;
import cppconvhelpers;

struct QListData {
    struct NotIndirectLayout {}
    struct ArrayCompatibleLayout {
        NotIndirectLayout base0;
        alias base0 this;
}
}

