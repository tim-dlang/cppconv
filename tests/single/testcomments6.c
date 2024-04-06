#define f(a, b, c) 1
int i1 = /*commenta1*/f/*commenta2*/(/*commenta3*/1/*commenta4*/,/*commenta5*/2/*commenta6*/,/*commenta7*/3/*commenta8*/)/*commenta9*/;

#define X /*commentb1*/f/*commentb2*/(/*commentb3*/4/*commentb4*/,/*commentb5*/5/*commentb6*/,/*commentb7*/6/*commentb8*/)/*commentb9*/
int i2 = X;

#define g(b) /*commentc1*/f/*commentc2*/(/*commentc3*/7/*commentc4*/,/*commentc5*/b/*commentc6*/,/*commentc7*/9/*commentc8*/)/*commentc9*/
int i3 = /*commentd1*/g/*commentd2*/(/*commentd3*/8/*commentd4*/)/*commentd5*/;

#define h(b) /*commente1*/g/*commente2*/(/*commente3*/f/*commente4*/(/*commente5*/,/*commente6*/,/*commente7*/)/*commente8*/)/*commente9*/
int i4 = /*commentf1*/h/*commentf2*/(/*commentf3*/10/*commentf4*/)/*commentf5*/;/*commentf6*/
