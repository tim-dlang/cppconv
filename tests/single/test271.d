
module test271;

import config;
import cppconvhelpers;

struct QGenericMatrix(int N, int M, T)
{
}

alias QMatrix2x2 = QGenericMatrix!(2, 2, float);
alias QMatrix2x3 = QGenericMatrix!(2, 3, float);

