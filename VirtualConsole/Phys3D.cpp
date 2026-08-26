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

    playerHalfX = playerHalfY = playerHalfZ = 0;
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

    case REG_PLAYER_HALF_X: return playerHalfX;
    case REG_PLAYER_HALF_Y: return playerHalfY;
    case REG_PLAYER_HALF_Z: return playerHalfZ;
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

    case REG_PLAYER_HALF_X: playerHalfX = value; return;
    case REG_PLAYER_HALF_Y: playerHalfY = value; return;
    case REG_PLAYER_HALF_Z: playerHalfZ = value; return;

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
    // Перекрытие двух отрезков [aMin,aMax] и [bMin,bMax] - используется
    // на каждой паре осей при проверке AABB-пересечения ниже.
    bool overlaps1D(double aCenter, double aHalf, double bCenter, double bHalf)
    {
        return std::abs(aCenter - bCenter) < (aHalf + bHalf);
    }
}

void Phys3D::moveResolveX(double& px, double py, double pz, double dx) const
{
    double newPx = px + dx;

    for (const Box& box : boxes)
    {
        if (!box.active) { continue; }
        if (!overlaps1D(py, playerHalfY, box.y, box.halfY)) { continue; }
        if (!overlaps1D(pz, playerHalfZ, box.z, box.halfZ)) { continue; }
        if (!overlaps1D(newPx, playerHalfX, box.x, box.halfX)) { continue; }

        // Пересеклись по всем трём осям при позиции newPx - вытолкнуть
        // вдоль X на ближайшую грань бокса (в ту сторону, откуда пришли).
        if (dx > 0)
        {
            newPx = box.x - box.halfX - playerHalfX;
        }
        else if (dx < 0)
        {
            newPx = box.x + box.halfX + playerHalfX;
        }
    }

    px = newPx;
}

void Phys3D::moveResolveZ(double px, double& pz, double py, double dz) const
{
    double newPz = pz + dz;

    for (const Box& box : boxes)
    {
        if (!box.active) { continue; }
        if (!overlaps1D(py, playerHalfY, box.y, box.halfY)) { continue; }
        if (!overlaps1D(px, playerHalfX, box.x, box.halfX)) { continue; }
        if (!overlaps1D(newPz, playerHalfZ, box.z, box.halfZ)) { continue; }

        if (dz > 0)
        {
            newPz = box.z - box.halfZ - playerHalfZ;
        }
        else if (dz < 0)
        {
            newPz = box.z + box.halfZ + playerHalfZ;
        }
    }

    pz = newPz;
}

void Phys3D::moveResolveY(double px, double pz, double& py, double dy)
{
    double newPy = py + dy;
    bool landedOnSomething = false;

    for (const Box& box : boxes)
    {
        if (!box.active) { continue; }
        if (!overlaps1D(px, playerHalfX, box.x, box.halfX)) { continue; }
        if (!overlaps1D(pz, playerHalfZ, box.z, box.halfZ)) { continue; }
        if (!overlaps1D(newPy, playerHalfY, box.y, box.halfY)) { continue; }

        if (dy > 0)
        {
            newPy = box.y - box.halfY - playerHalfY;
            landedOnSomething = true;
        }
        else if (dy < 0)
        {
            newPy = box.y + box.halfY + playerHalfY;
        }

        velocityY = 0.0;
    }

    // Бесконечная опорная плоскость пола ("горизонт") - игрок не может
    // провалиться сквозь GROUND_Y ни при каких X/Z, в отличие от боксов
    // с конечными границами выше. Конвенция: "вниз" = РОСТ Y (гравитация
    // прибавляется к velocityY со знаком +, см. step()) - если на живом
    // запуске окажется, что визуально это "вверх", поменять знак
    // гравитации в step() на противоположный, здесь менять ничего не
    // придётся (пол по-прежнему "там, где движение с dy>0").
    double groundY = combine(groundYLow, groundYHigh);

    if (dy > 0 && newPy + playerHalfY >= groundY)
    {
        newPy = groundY - playerHalfY;
        landedOnSomething = true;
        velocityY = 0.0;
    }

    grounded = landedOnSomething ? 1 : 0;
    py = newPy;
}

void Phys3D::step()
{
    double px = combine(playerXLow, playerXHigh);
    double py = combine(playerYLow, playerYHigh);
    double pz = combine(playerZLow, playerZHigh);

    double dx = combine(moveDxLow, moveDxHigh);
    double dy = combine(moveDyLow, moveDyHigh);
    double dz = combine(moveDzLow, moveDzHigh);

    // Гравитация - копится в velocityY, обнуляется moveResolveY() при
    // посадке на пол/бокс. Направление "вниз" - в сторону РОСТА Y (та
    // же конвенция, что и у пола ниже: посадка происходит при движении
    // с dy > 0) - если на живом запуске оси наоборот, поменять знак
    // здесь и в moveResolveY на противоположный.
    double gravity = combine(gravityLow, gravityHigh);
    velocityY += gravity;

    moveResolveX(px, py, pz, dx);
    moveResolveZ(px, pz, py, dz);
    moveResolveY(px, pz, py, dy + velocityY);

    split(static_cast<int16_t>(std::lround(px)), playerXLow, playerXHigh);
    split(static_cast<int16_t>(std::lround(py)), playerYLow, playerYHigh);
    split(static_cast<int16_t>(std::lround(pz)), playerZLow, playerZHigh);

    stepStatus = 0;
}
