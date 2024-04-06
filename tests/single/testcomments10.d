module testcomments10;

import config;
import cppconvhelpers;

/*commenta1*/
 mixin(q{enum xmlElementType/*commenta3*/
    }
    ~ "{"
    ~ q{
    /*commenta4*/
        /*commentb1*/XML_ELEMENT_NODE/*commentb2*/=/*commentb3*/1/*commentb4*/,/*commentb5*/
        /*commentc1*/XML_ATTRIBUTE_NODE/*commentc2*/=/*commentc3*/2/*commentc4*/,/*commentc5*/
    }
    ~ (defined!"DEF" ? q{
    /+ #ifdef DEF +/
        /*commentd1*/XML_ATTRIBUTE_TEST/*commentd2*/=/*commentd3*/3/*commentd4*/,
    }:"")
    ~ q{
    /*commentd5*/
    /+ #endif +/
        /*commente1*/XML_XINCLUDE_END/*commente2*/=/*commente3*/20/*commente4*/
    }
    ~ (defined!"DEF" ? q{
    /+ #ifdef DEF +/
       /*commentf1*/,/*commentf2*/XML_DOCB_DOCUMENT_NODE/*commentf3*/=/*commentf4*/21/*commentf5*/
    /+ #endif +/
    /*commentg1*/
    }:"")
    ~ "}"
);
/*commenta2*/// self alias: alias xmlElementType = xmlElementType/*commentg2*//*commentg3*/;/*commentg4*/

/*commenth1*/
__gshared xmlElementType/*commenth2*/ x1/*commenth3*/=/*commenth4*/xmlElementType.XML_ELEMENT_NODE/*commenth5*/;/*commenth6*/
/*commenti1*/
__gshared xmlElementType/*commenti2*/ x2/*commenti3*/=/*commenti4*/xmlElementType.XML_ATTRIBUTE_NODE/*commenti5*/;/*commenti6*/
static if (defined!"DEF")
{
/*commentj1*/
__gshared xmlElementType/*commentj2*/ x3/*commentj3*/=/*commentj4*/xmlElementType.XML_ATTRIBUTE_TEST/*commentj5*/;/*commentj6*/
}
/*commentk1*/
__gshared xmlElementType/*commentk2*/ x4/*commentk3*/=/*commentk4*/xmlElementType.XML_XINCLUDE_END/*commentk5*/;/*commentk6*/
static if (defined!"DEF")
{
/*commentl1*/
__gshared xmlElementType/*commentl2*/ x5/*commentl3*/=/*commentl4*/xmlElementType.XML_DOCB_DOCUMENT_NODE/*commentl5*/;/*commentl6*/
}
/*commentend*/

