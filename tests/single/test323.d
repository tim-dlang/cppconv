
module test323;

import config;
import cppconvhelpers;

struct QFuture(T)
{
}
struct QFutureInterface(T)
{
}
struct QtFuture
{
	enum Launch
	{
		Launch0
	}
}
struct Function
{
}

extern(C++, class) struct Continuation(Function, ResultType, ParentResultType)
{
private:
    /+ template<typename F = Function> +/
    /+ static void create(F &&func, QFuture<ParentResultType> *f, QFutureInterface<ResultType> &p,
                       QtFuture::Launch policy); +/
}


/+ template<typename Function, typename ResultType, typename ParentResultType>
template<typename F>
void Continuation<Function, ResultType, ParentResultType>::create(F &&func,
                                                                  QFuture<ParentResultType> *f,
                                                                  QFutureInterface<ResultType> &p,
                                                                  QtFuture::Launch policy)
{
} +/

