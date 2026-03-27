struct S
{
    int i;
    S(int i) : i(i)
    {}

    S operator +() { return S(+this->i); }
    S operator -() { return S(-this->i); }
    S operator *() { return S(this->i); }
    S operator ~() { return S(~this->i); }
    S operator ++() { ++this->i; return *this; }
    S operator --() { --this->i; return *this; }

    S operator +(S rhs) { return S(this->i + rhs.i); }
    S operator -(S rhs) { return S(this->i - rhs.i); }
    S operator *(S rhs) { return S(this->i * rhs.i); }
    S operator /(S rhs) { return S(this->i / rhs.i); }
    S operator %(S rhs) { return S(this->i % rhs.i); }
    S operator &(S rhs) { return S(this->i & rhs.i); }
    S operator |(S rhs) { return S(this->i | rhs.i); }
    S operator ^(S rhs) { return S(this->i ^ rhs.i); }

    S &operator +=(S rhs) { this->i += rhs.i; return *this; }
    S &operator -=(S rhs) { this->i -= rhs.i; return *this; }
    S &operator *=(S rhs) { this->i *= rhs.i; return *this; }
    S &operator /=(S rhs) { this->i /= rhs.i; return *this; }
    S &operator %=(S rhs) { this->i %= rhs.i; return *this; }
    S &operator &=(S rhs) { this->i &= rhs.i; return *this; }
    S &operator |=(S rhs) { this->i |= rhs.i; return *this; }
    S &operator ^=(S rhs) { this->i ^= rhs.i; return *this; }
};

void f()
{
    S a(1);
    S b(2);
    S c(3);

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
