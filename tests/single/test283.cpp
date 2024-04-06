
class QVector2D
{
public:
    QVector2D();
    QVector2D(float xpos, float ypos);
private:
    float v[2];
};


inline QVector2D::QVector2D(float xpos, float ypos) : v{xpos, ypos} {}
