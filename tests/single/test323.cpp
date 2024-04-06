
template<typename T>
struct QFuture
{
};
template<typename T>
struct QFutureInterface
{
};
struct QtFuture
{
	enum Launch
	{
		Launch0
	};
};
struct Function
{
};

template<typename Function, typename ResultType, typename ParentResultType>
class Continuation
{
    template<typename F = Function>
    static void create(F &&func, QFuture<ParentResultType> *f, QFutureInterface<ResultType> &p,
                       QtFuture::Launch policy);
};


template<typename Function, typename ResultType, typename ParentResultType>
template<typename F>
void Continuation<Function, ResultType, ParentResultType>::create(F &&func,
                                                                  QFuture<ParentResultType> *f,
                                                                  QFutureInterface<ResultType> &p,
                                                                  QtFuture::Launch policy)
{
}
