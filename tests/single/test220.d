module test220;

import config;
import cppconvhelpers;

alias ush = int;
union generated_test220_0{ush freq;ush code;}
union generated_test220_1{ush dad;ush len;}
struct ct_data_s {
    generated_test220_0 fc;
    generated_test220_1 dl;
}
alias ct_data = ct_data_s;

__gshared const(ct_data)[5] static_ltree = [
const(ct_data_s)(generated_test220_0( 12),generated_test220_1(  8)), const(ct_data_s)(generated_test220_0(140),generated_test220_1(  8)), const(ct_data_s)(generated_test220_0( 76),generated_test220_1(  8)), const(ct_data_s)(generated_test220_0(204),generated_test220_1(  8)), const(ct_data_s)(generated_test220_0( 44),generated_test220_1(  8)),]
;

