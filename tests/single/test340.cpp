
class QPixmap
{
    inline QPixmap copy(int x, int y, int width, int height) const;

    class Local;
};

inline QPixmap QPixmap::copy(int ax, int ay, int awidth, int aheight) const
{
    return QPixmap();
}

class QPixmap::Local
{

};
