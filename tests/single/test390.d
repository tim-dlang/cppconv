module test390;

import config;
import cppconvhelpers;

struct S
{
    int i;
    this(int i)
    {
        this.i = i;
    }

    S opUnary(string op)() if (op == "+") { return S(+this.i); }
    S opUnary(string op)() if (op == "-") { return S(-this.i); }
    S opUnary(string op)() if (op == "*") { return S(this.i); }
    S opUnary(string op)() if (op == "~") { return S(~this.i); }
    S opUnary(string op)() if (op == "++") { ++this.i; return this; }
    S opUnary(string op)() if (op == "--") { --this.i; return this; }

    S opBinary(string op)(S rhs) if (op == "+") { return S(this.i + rhs.i); }
    S opBinary(string op)(S rhs) if (op == "-") { return S(this.i - rhs.i); }
    S opBinary(string op)(S rhs) if (op == "*") { return S(this.i * rhs.i); }
    S opBinary(string op)(S rhs) if (op == "/") { return S(this.i / rhs.i); }
    S opBinary(string op)(S rhs) if (op == "%") { return S(this.i % rhs.i); }
    S opBinary(string op)(S rhs) if (op == "&") { return S(this.i & rhs.i); }
    S opBinary(string op)(S rhs) if (op == "|") { return S(this.i | rhs.i); }
    S opBinary(string op)(S rhs) if (op == "^") { return S(this.i ^ rhs.i); }

    ref S opOpAssign(string op)(S rhs) if (op == "+") { this.i += rhs.i; return this; }
    ref S opOpAssign(string op)(S rhs) if (op == "-") { this.i -= rhs.i; return this; }
    ref S opOpAssign(string op)(S rhs) if (op == "*") { this.i *= rhs.i; return this; }
    ref S opOpAssign(string op)(S rhs) if (op == "/") { this.i /= rhs.i; return this; }
    ref S opOpAssign(string op)(S rhs) if (op == "%") { this.i %= rhs.i; return this; }
    ref S opOpAssign(string op)(S rhs) if (op == "&") { this.i &= rhs.i; return this; }
    ref S opOpAssign(string op)(S rhs) if (op == "|") { this.i |= rhs.i; return this; }
    ref S opOpAssign(string op)(S rhs) if (op == "^") { this.i ^= rhs.i; return this; }
}

void f()
{
    auto a = S(1);
    auto b = S(2);
    auto c = S(3);

    c = +a;
    c = -a;
    c = *a;
    c = ~a;
    ++a;
    --a;

    a = b + c;
    a = b - c;
    a = b * c;
    a = b / c;
    a = b % c;
    a = b & c;
    a = b | c;
    a = b ^ c;

    a += b;
    a -= b;
    a *= b;
    a /= b;
    a %= b;
    a &= b;
    a |= b;
    a ^= b;
}

static if (!defined!"DEF")
{
struct S2
{
    S2 opBinary(string op)(S2 rhs) if (op == "+") { return S2(); }
}
}

