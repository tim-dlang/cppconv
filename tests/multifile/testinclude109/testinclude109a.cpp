#include "testinclude109b.h"

class Child : public Base
{
public:
    ~Child() override {}
    void f() override {}
    void g() override;
};

void Child::g()
{
}
