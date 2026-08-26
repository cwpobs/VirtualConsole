#include "Phys3D.h"

#include <algorithm>
#include <cmath>

Phys3D::Phys3D()
{
    groundYLow = groundYHigh = 0;
    gravityLow = 0;
    gravityHigh = 0;

    boxSlot = 0;
    boxXLow = boxXHigh = boxYLow = boxYHigh = boxZLow = boxZHigh = 0;
    boxHalfX = boxHalfY = boxHalfZ = 0;
    boxStatus = 0;

    playerRadius = 0;
    playerXLow = playerXHigh = playerYLow = playerYHigh = playerZLow = playerZHigh = 0;

    moveDxLow = moveDxHigh = moveDyLow = moveDyHigh = moveDzLow = moveDzHigh = 0;

    grounded = 0;
    stepStatus = 0;
    velocityY = 0.0;

    boxes.assign(MAX_BOXES, Box{ false, 0, 0, 0, 0, 0, 0 });
}

int16_t Phys3D::combine(uint8_t low, uint8_t high)
{
    return static_cast<int16_t>(static_cast<uint16_t>(low) | (static_cast<uint16_t>(high) << 8));
}

void Phys3D::split(int16_t value, uint8_t& low, uint8_t& high)
{
    uint16_t bits = static_cast<uint16_t>(value);
    low = static_cast<uint8_t>(bits & 0xFF);
    high = static_cast<uint8_t>((bits >> 8) & 0xFF);
}

uint8_t Phys3D::read(uint32_t address)
{
    switch (address)
    {
    case REG_GROUND_Y_LOW: return groundYLow;
    case REG_GROUND_Y_HIGH: return groundYHigh;
    case REG_GRAVITY_LOW: return gravityLow;
    case REG_GRAVITY_HIGH: return gravityHigh;

    case REG_BOX_SLOT: return boxSlot;
    case REG_BOX_X_LOW: return boxXLow;
    case REG_BOX_X_HIGH: return boxXHigh;
    case REG_BOX_Y_LOW: return boxYLow;
    case REG_BOX_Y_HIGH: return boxYHigh;
    case REG_BOX_Z_LOW: return boxZLow;
    case REG_BOX_Z_HIGH: return boxZHigh;
    case REG_BOX_HALF_X: return boxHalfX;
    case REG_BOX_HALF_Y: return boxHalfY;
    case REG_BOX_HALF_Z: return boxHalfZ;
    case REG_BOX_STATUS: return boxStatus;

    case REG_PLAYER_RADIUS: return playerRadius;
    case REG_PLAYER_X_LOW: return playerXLow;
    case REG_PLAYER_X_HIGH: return playerXHigh;
    case REG_PLAYER_Y_LOW: return playerYLow;
    case REG_PLAYER_Y_HIGH: return playerYHigh;
    case REG_PLAYER_Z_LOW: return playerZLow;
    case REG_PLAYER_Z_HIGH: return playerZHigh;

    case REG_MOVE_DX_LOW: return moveDxLow;
    case REG_MOVE_DX_HIGH: return moveDxHigh;
    case REG_MOVE_DY_LOW: return moveDyLow;
    case REG_MOVE_DY_HIGH: return moveDyHigh;
    case REG_MOVE_DZ_LOW: return moveDzLow;
    case REG_MOVE_DZ_HIGH: return moveDzHigh;

    case REG_GROUNDED: return grounded;
    case REG_STEP_STATUS: return stepStatus;

    default: return 0;
    }
}

void Phys3D::write(uint32_t address, uint8_t value)
{
    switch (address)
    {
    case REG_GROUND_Y_LOW: groundYLow = value; return;
    case REG_GROUND_Y_HIGH: groundYHigh = value; return;
    case REG_GRAVITY_LOW: gravityLow = value; return;
    case REG_GRAVITY_HIGH: gravityHigh = value; return;

    case REG_BOX_SLOT: boxSlot = value; return;
    case REG_BOX_X_LOW: boxXLow = value; return;
    case REG_BOX_X_HIGH: boxXHigh = value; return;
    case REG_BOX_Y_LOW: boxYLow = value; return;
    case REG_BOX_Y_HIGH: boxYHigh = value; return;
    case REG_BOX_Z_LOW: boxZLow = value; return;
    case REG_BOX_Z_HIGH: boxZHigh = value; return;
    case REG_BOX_HALF_X: boxHalfX = value; return;
    case REG_BOX_HALF_Y: boxHalfY = value; return;
    case REG_BOX_HALF_Z: boxHalfZ = value; return;

    case REG_BOX_COMMAND:
        switch (value)
        {
        case 1: defineBox(); break;
        case 2: clearAllBoxes(); break;
        default: break;
        }
        return;

    case REG_PLAYER_RADIUS: playerRadius = value; return;

    // Позиция игрока пишется напрямую, без проверки коллизий - спавн/
    // телепорт, как OBJ_X у Gpu3D. Разрешённая позиция после движения
    // читается обратно этими же регистрами (см. step()).
    case REG_PLAYER_X_LOW: playerXLow = value; return;
    case REG_PLAYER_X_HIGH: playerXHigh = value; return;
    case REG_PLAYER_Y_LOW: playerYLow = value; return;
    case REG_PLAYER_Y_HIGH: playerYHigh = value; return;
    case REG_PLAYER_Z_LOW: playerZLow = value; return;
    case REG_PLAYER_Z_HIGH: playerZHigh = value; return;

    case REG_MOVE_DX_LOW: moveDxLow = value; return;
    case REG_MOVE_DX_HIGH: moveDxHigh = value; return;
    case REG_MOVE_DY_LOW: moveDyLow = value; return;
    case REG_MOVE_DY_HIGH: moveDyHigh = value; return;
    case REG_MOVE_DZ_LOW: moveDzLow = value; return;
    case REG_MOVE_DZ_HIGH: moveDzHigh = value; return;

    case REG_STEP_COMMAND:
        if (value == 1) { step(); }
        return;

    default:
        return;
    }
}

void Phys3D::defineBox()
{
    if (boxSlot >= MAX_BOXES)
    {
        boxStatus = 1;
        return;
    }

    Box& box = boxes[boxSlot];
    box.active = true;
    box.x = combine(boxXLow, boxXHigh);
    box.y = combine(boxYLow, boxYHigh);
    box.z = combine(boxZLow, boxZHigh);
    box.halfX = boxHalfX;
    box.halfY = boxHalfY;
    box.halfZ = boxHalfZ;

    boxStatus = 0;
}

void Phys3D::clearAllBoxes()
{
    for (Box& box : boxes)
    {
        box.active = false;
    }

    boxStatus = 0;
}

namespace
{
    // Небольшой запас сверх "ровно касается" - без него камера
    // останавливается точно на поверхности грани, а без backface
    // culling в растеризаторе Gpu3D (см. ASSEMBLY.md) на этой границе
    // из-за погрешности плавающей точки при повороте камеры видны
    // внутренние грани куба - тот же класс проблемы, что и z-fighting
    // между соседними кубами (см. CUBE_DRAW_HALF в CUBEWRLD.MC). Держит
    // сферу игрока чуть дальше от любой грани, чем "впритык".
    const double COLLISION_SKIN = 2.0;
}

void Phys3D::resolveSphereBoxes(double& px, double& py, double& pz)
{
    double radius = playerRadius;

    for (const Box& box : boxes)
    {
        if (!box.active) { continue; }

        // Ближайшая точка на AABB к центру сферы - покоординатный clamp.
        double closestX = std::min(std::max(px, box.x - box.halfX), box.x + box.halfX);
        double closestY = std::min(std::max(py, box.y - box.halfY), box.y + box.halfY);
        double closestZ = std::min(std::max(pz, box.z - box.halfZ), box.z + box.halfZ);

        double dx = px - closestX;
        double dy = py - closestY;
        double dz = pz - closestZ;
        double distSq = dx * dx + dy * dy + dz * dz;

        if (distSq >= radius * radius) { continue; }

        double dist = std::sqrt(distSq);
        double nx, ny, nz;

        if (dist > 1e-6)
        {
            nx = dx / dist;
            ny = dy / dist;
            nz = dz / dist;
        }
        else
        {
            // Вырожденный случай - центр сферы совпал с ближайшей точкой
            // (центр внутри бокса) - выталкиваем "вверх" (см. ниже про
            // конвенцию знака), чтобы не делить на ноль.
            nx = 0.0; ny = 1.0; nz = 0.0;
            dist = 0.0;
        }

        double push = radius - dist + COLLISION_SKIN;
        px += nx * push;
        py += ny * push;
        pz += nz * push;

        // "Вверх" - это +Y (подтверждено живым тестом на стопке кубов -
        // второй блок стены рисуется на +CUBE_SIZE и стоит НАД первым,
        // см. CUBEWRLD.MC/misty-zooming-bee.md) - если вытолкнуло
        // преимущественно в эту сторону, считаем, что игрок приземлился
        // НА бокс сверху.
        if (ny > 0.5)
        {
            grounded = 1;
            velocityY = 0.0;
        }
    }
}

void Phys3D::resolveGroundPlane(double& py)
{
    // Бесконечная опорная плоскость пола ("горизонт") - игрок не может
    // провалиться сквозь GROUND_Y ни при каких X/Z, в отличие от боксов
    // с конечными границами выше. Конвенция: "вверх" = РОСТ Y (см. выше) -
    // игрок падает при УМЕНЬШЕНИИ Y и должен упереться в пол снизу,
    // когда его нижняя точка (py - radius) достигает GROUND_Y.
    double groundY = combine(groundYLow, groundYHigh);
    double radius = playerRadius;

    if (py - radius <= groundY)
    {
        py = groundY + radius + COLLISION_SKIN;
        grounded = 1;
        velocityY = 0.0;
    }
}

void Phys3D::step()
{
    double px = combine(playerXLow, playerXHigh);
    double py = combine(playerYLow, playerYHigh);
    double pz = combine(playerZLow, playerZHigh);

    double dx = combine(moveDxLow, moveDxHigh);
    double dy = combine(moveDyLow, moveDyHigh);
    double dz = combine(moveDzLow, moveDzHigh);

    // Гравитация - копится в velocityY, обнуляется при посадке
    // (resolveSphereBoxes/resolveGroundPlane). "Вверх" = РОСТ Y (см.
    // resolveGroundPlane/resolveSphereBoxes), значит падение - это
    // УМЕНЬШЕНИЕ Y, отсюда минус: GRAVITY - положительная величина
    // ("сколько юнитов/кадр² теряем"), а не знаковое ускорение.
    double gravity = combine(gravityLow, gravityHigh);
    velocityY -= gravity;

    // Сфера двигается СРАЗУ на полный вектор (не по осям отдельно, как
    // раньше - см. misty-zooming-bee.md про "срезание углов") - вся
    // работа по недопущению проникновения в геометрию - в
    // resolveSphereBoxes ниже.
    px += dx;
    py += dy + velocityY;
    pz += dz;

    grounded = 0;
    resolveSphereBoxes(px, py, pz);
    resolveGroundPlane(py);

    split(static_cast<int16_t>(std::lround(px)), playerXLow, playerXHigh);
    split(static_cast<int16_t>(std::lround(py)), playerYLow, playerYHigh);
    split(static_cast<int16_t>(std::lround(pz)), playerZLow, playerZHigh);

    stepStatus = 0;
}
