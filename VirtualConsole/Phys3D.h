#pragma once

#include "Device.h"

#include <cstdint>
#include <vector>

// Физический ускоритель - отдельное устройство (сознательно НЕ связано
// с Gpu3D в этом заходе, см. misty-zooming-bee.md - может быть спарено
// позже, но это отдельная задача). Считает гравитацию, AABB-примитивы
// ("объёмы"), коллизии игрока с ними и с бесконечной опорной плоскостью
// пола ("горизонт") - вся математика на стороне C++, тем же
// рассуждением, что и у Gpu3D: наш процессор слабый, устройство - нет.
//
// Ключевое архитектурное решение (чтобы не повторить ошибку первой
// версии CUBEWRLD.MC с сотнями poke() на кадр): статичные боксы уровня
// определяются ОДИН РАЗ при загрузке (DEFINE_BOX, как текстуры/карта -
// "определи и забудь"), а не пересылаются каждый кадр. За кадр по шине
// идёт только одна команда STEP - "подвинь игрока на (dx,dy,dz),
// разреши коллизии" - перебор всех боксов делает C++ внутри.
class Phys3D : public Device
{
public:

    Phys3D();

    uint8_t read(uint32_t address) override;
    void write(uint32_t address, uint8_t value) override;

private:

    static const int MAX_BOXES = 128;

    static const uint32_t REG_GROUND_Y_LOW = 0;
    static const uint32_t REG_GROUND_Y_HIGH = 1;
    static const uint32_t REG_GRAVITY_LOW = 2;
    static const uint32_t REG_GRAVITY_HIGH = 3;

    static const uint32_t REG_BOX_SLOT = 4;
    static const uint32_t REG_BOX_X_LOW = 5;
    static const uint32_t REG_BOX_X_HIGH = 6;
    static const uint32_t REG_BOX_Y_LOW = 7;
    static const uint32_t REG_BOX_Y_HIGH = 8;
    static const uint32_t REG_BOX_Z_LOW = 9;
    static const uint32_t REG_BOX_Z_HIGH = 10;
    static const uint32_t REG_BOX_HALF_X = 11;
    static const uint32_t REG_BOX_HALF_Y = 12;
    static const uint32_t REG_BOX_HALF_Z = 13;
    static const uint32_t REG_BOX_COMMAND = 14;
    static const uint32_t REG_BOX_STATUS = 15;

    // Игрок - сфера (один радиус), не AABB - см. misty-zooming-bee.md:
    // раздельное разрешение по осям (X/Z/Y по очереди) даёт "срезание
    // углов" при движении по диагонали в угол куба, из-за чего камера
    // на кадр оказывалась внутри геометрии. Сфера против AABB-боксов
    // (боксы остаются AABB) выталкивается вдоль НАСТОЯЩЕГО направления
    // проникновения - углов не режет. Смещения 17-18 (бывшие
    // PLAYER_HALF_Y/Z) теперь ничем не заняты - не переносим 19 и
    // дальше, чтобы не сдвигать остальные регистры без необходимости.
    static const uint32_t REG_PLAYER_RADIUS = 16;
    static const uint32_t REG_PLAYER_X_LOW = 19;
    static const uint32_t REG_PLAYER_X_HIGH = 20;
    static const uint32_t REG_PLAYER_Y_LOW = 21;
    static const uint32_t REG_PLAYER_Y_HIGH = 22;
    static const uint32_t REG_PLAYER_Z_LOW = 23;
    static const uint32_t REG_PLAYER_Z_HIGH = 24;

    static const uint32_t REG_MOVE_DX_LOW = 25;
    static const uint32_t REG_MOVE_DX_HIGH = 26;
    static const uint32_t REG_MOVE_DY_LOW = 27;
    static const uint32_t REG_MOVE_DY_HIGH = 28;
    static const uint32_t REG_MOVE_DZ_LOW = 29;
    static const uint32_t REG_MOVE_DZ_HIGH = 30;

    static const uint32_t REG_GROUNDED = 31;
    static const uint32_t REG_STEP_COMMAND = 32;
    static const uint32_t REG_STEP_STATUS = 33;

    struct Box
    {
        bool active;
        double x, y, z;
        double halfX, halfY, halfZ;
    };

    uint8_t groundYLow, groundYHigh;
    uint8_t gravityLow, gravityHigh;

    uint8_t boxSlot;
    uint8_t boxXLow, boxXHigh, boxYLow, boxYHigh, boxZLow, boxZHigh;
    uint8_t boxHalfX, boxHalfY, boxHalfZ;
    uint8_t boxStatus;

    uint8_t playerRadius;
    uint8_t playerXLow, playerXHigh, playerYLow, playerYHigh, playerZLow, playerZHigh;

    uint8_t moveDxLow, moveDxHigh, moveDyLow, moveDyHigh, moveDzLow, moveDzHigh;

    uint8_t grounded;
    uint8_t stepStatus;

    double velocityY;

    std::vector<Box> boxes;   // MAX_BOXES

    static int16_t combine(uint8_t low, uint8_t high);
    static void split(int16_t value, uint8_t& low, uint8_t& high);

    void defineBox();
    void clearAllBoxes();
    void step();

    // Sphere-vs-AABB для каждого активного бокса: ближайшая точка на
    // боксе к центру сферы, выталкивание вдоль вектора (центр -
    // ближайшая точка) - см. misty-zooming-bee.md про то, почему это
    // заменило три раздельных прохода по осям (срезало углы кубов).
    // Мутирует px/py/pz на месте, взводит grounded/обнуляет velocityY
    // при выталкивании преимущественно "вверх" (см. resolveSphereBoxes).
    void resolveSphereBoxes(double& px, double& py, double& pz);

    // Плоскость пола - отдельно от боксов (бесконечна, не AABB).
    void resolveGroundPlane(double& py);
};
