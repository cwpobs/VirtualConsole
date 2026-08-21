#include "Gpu3D.h"
#include "VideoCard.h"

#include <algorithm>
#include <cmath>
#include <limits>

namespace
{
    const double PI = 3.14159265358979323846;
    const double FOV_DEGREES = 70.0;

    double degToRad(double deg)
    {
        return deg * PI / 180.0;
    }
}

Gpu3D::Gpu3D(VideoCard* videoCard)
    : videoCard(videoCard)
{
    vxLow = vxHigh = vyLow = vyHigh = vzLow = vzHigh = 0;
    vr = vg = vb = 0;
    status = 0;

    objXLow = objXHigh = objYLow = objYHigh = objZLow = objZHigh = 0;
    objYawLow = objYawHigh = objPitchLow = objPitchHigh = objRollLow = objRollHigh = 0;

    camXLow = camXHigh = camYLow = camYHigh = camZLow = camZHigh = 0;
    camYawLow = camYawHigh = camPitchLow = camPitchHigh = 0;

    pendingCount = 0;

    zBuffer.assign(WIDTH * HEIGHT, std::numeric_limits<float>::infinity());
    colorBuffer.assign(WIDTH * HEIGHT * 3, 0);
    touchedMask.assign(WIDTH * HEIGHT, 0);
}

int16_t Gpu3D::combine(uint8_t low, uint8_t high)
{
    return static_cast<int16_t>(static_cast<uint16_t>(low) | (static_cast<uint16_t>(high) << 8));
}

uint8_t Gpu3D::read(uint32_t address)
{
    switch (address)
    {
    case REG_VX_LOW: return vxLow;
    case REG_VX_HIGH: return vxHigh;
    case REG_VY_LOW: return vyLow;
    case REG_VY_HIGH: return vyHigh;
    case REG_VZ_LOW: return vzLow;
    case REG_VZ_HIGH: return vzHigh;
    case REG_VR: return vr;
    case REG_VG: return vg;
    case REG_VB: return vb;
    case REG_STATUS: return status;

    case REG_OBJ_X_LOW: return objXLow;
    case REG_OBJ_X_HIGH: return objXHigh;
    case REG_OBJ_Y_LOW: return objYLow;
    case REG_OBJ_Y_HIGH: return objYHigh;
    case REG_OBJ_Z_LOW: return objZLow;
    case REG_OBJ_Z_HIGH: return objZHigh;
    case REG_OBJ_YAW_LOW: return objYawLow;
    case REG_OBJ_YAW_HIGH: return objYawHigh;
    case REG_OBJ_PITCH_LOW: return objPitchLow;
    case REG_OBJ_PITCH_HIGH: return objPitchHigh;
    case REG_OBJ_ROLL_LOW: return objRollLow;
    case REG_OBJ_ROLL_HIGH: return objRollHigh;

    case REG_CAM_X_LOW: return camXLow;
    case REG_CAM_X_HIGH: return camXHigh;
    case REG_CAM_Y_LOW: return camYLow;
    case REG_CAM_Y_HIGH: return camYHigh;
    case REG_CAM_Z_LOW: return camZLow;
    case REG_CAM_Z_HIGH: return camZHigh;
    case REG_CAM_YAW_LOW: return camYawLow;
    case REG_CAM_YAW_HIGH: return camYawHigh;
    case REG_CAM_PITCH_LOW: return camPitchLow;
    case REG_CAM_PITCH_HIGH: return camPitchHigh;

    default: return 0;
    }
}

void Gpu3D::write(uint32_t address, uint8_t value)
{
    switch (address)
    {
    case REG_VX_LOW: vxLow = value; return;
    case REG_VX_HIGH: vxHigh = value; return;
    case REG_VY_LOW: vyLow = value; return;
    case REG_VY_HIGH: vyHigh = value; return;
    case REG_VZ_LOW: vzLow = value; return;
    case REG_VZ_HIGH: vzHigh = value; return;
    case REG_VR: vr = value; return;
    case REG_VG: vg = value; return;
    case REG_VB: vb = value; return;

    case REG_COMMAND:
        switch (value)
        {
        case 1: submitVertex(); break;
        case 2: drawTriangle(); break;
        case 3: clear(); break;
        case 4: present(); break;
        default: break;
        }
        return;

    case REG_OBJ_X_LOW: objXLow = value; return;
    case REG_OBJ_X_HIGH: objXHigh = value; return;
    case REG_OBJ_Y_LOW: objYLow = value; return;
    case REG_OBJ_Y_HIGH: objYHigh = value; return;
    case REG_OBJ_Z_LOW: objZLow = value; return;
    case REG_OBJ_Z_HIGH: objZHigh = value; return;
    case REG_OBJ_YAW_LOW: objYawLow = value; return;
    case REG_OBJ_YAW_HIGH: objYawHigh = value; return;
    case REG_OBJ_PITCH_LOW: objPitchLow = value; return;
    case REG_OBJ_PITCH_HIGH: objPitchHigh = value; return;
    case REG_OBJ_ROLL_LOW: objRollLow = value; return;
    case REG_OBJ_ROLL_HIGH: objRollHigh = value; return;

    case REG_CAM_X_LOW: camXLow = value; return;
    case REG_CAM_X_HIGH: camXHigh = value; return;
    case REG_CAM_Y_LOW: camYLow = value; return;
    case REG_CAM_Y_HIGH: camYHigh = value; return;
    case REG_CAM_Z_LOW: camZLow = value; return;
    case REG_CAM_Z_HIGH: camZHigh = value; return;
    case REG_CAM_YAW_LOW: camYawLow = value; return;
    case REG_CAM_YAW_HIGH: camYawHigh = value; return;
    case REG_CAM_PITCH_LOW: camPitchLow = value; return;
    case REG_CAM_PITCH_HIGH: camPitchHigh = value; return;

    default:
        return;
    }
}

void Gpu3D::submitVertex()
{
    // Копится ровно 3 вершины на треугольник - четвёртая и далее (до
    // следующего DRAW_TRIANGLE/CLEAR) циклически перезаписывают буфер,
    // так же, как WRITE_PIXEL у спрайтов/тайлов работает по модулю
    // размера битмапа. Вызывающий код обязан слать SUBMIT_VERTEX
    // ровно 3 раза перед каждым DRAW_TRIANGLE (см. ASSEMBLY.md, "Gpu3D").
    int slot = pendingCount % 3;

    pendingVertices[slot].x = combine(vxLow, vxHigh);
    pendingVertices[slot].y = combine(vyLow, vyHigh);
    pendingVertices[slot].z = combine(vzLow, vzHigh);
    pendingVertices[slot].r = vr;
    pendingVertices[slot].g = vg;
    pendingVertices[slot].b = vb;

    pendingCount++;
    status = 0;
}

Gpu3D::ScreenVertex Gpu3D::transformAndProject(const Vertex& v) const
{
    double objX = combine(objXLow, objXHigh);
    double objY = combine(objYLow, objYHigh);
    double objZ = combine(objZLow, objZHigh);
    double yaw = degToRad(static_cast<int16_t>(combine(objYawLow, objYawHigh)) % 360);
    double pitch = degToRad(static_cast<int16_t>(combine(objPitchLow, objPitchHigh)) % 360);
    double roll = degToRad(static_cast<int16_t>(combine(objRollLow, objRollHigh)) % 360);

    // ---- модельная матрица: roll -> pitch -> yaw -> перенос ----

    double x = v.x, y = v.y, z = v.z;

    // roll (вокруг Z)
    double x1 = x * std::cos(roll) - y * std::sin(roll);
    double y1 = x * std::sin(roll) + y * std::cos(roll);
    double z1 = z;

    // pitch (вокруг X)
    double y2 = y1 * std::cos(pitch) - z1 * std::sin(pitch);
    double z2 = y1 * std::sin(pitch) + z1 * std::cos(pitch);
    double x2 = x1;

    // yaw (вокруг Y)
    double x3 = x2 * std::cos(yaw) + z2 * std::sin(yaw);
    double z3 = -x2 * std::sin(yaw) + z2 * std::cos(yaw);
    double y3 = y2;

    double worldX = x3 + objX;
    double worldY = y3 + objY;
    double worldZ = z3 + objZ;

    // ---- камера: перенос -> отмена pitch -> отмена yaw (без крена) ----

    double camX = combine(camXLow, camXHigh);
    double camY = combine(camYLow, camYHigh);
    double camZ = combine(camZLow, camZHigh);
    double camYaw = degToRad(static_cast<int16_t>(combine(camYawLow, camYawHigh)) % 360);
    double camPitch = degToRad(static_cast<int16_t>(combine(camPitchLow, camPitchHigh)) % 360);

    double rx = worldX - camX;
    double ry = worldY - camY;
    double rz = worldZ - camZ;

    // отменяем yaw камеры
    double vx1 = rx * std::cos(-camYaw) + rz * std::sin(-camYaw);
    double vz1 = -rx * std::sin(-camYaw) + rz * std::cos(-camYaw);
    double vy1 = ry;

    // отменяем pitch камеры
    double vy2 = vy1 * std::cos(-camPitch) - vz1 * std::sin(-camPitch);
    double vz2 = vy1 * std::sin(-camPitch) + vz1 * std::cos(-camPitch);
    double vx2 = vx1;

    ScreenVertex out;
    out.viewZ = vz2;
    out.r = v.r;
    out.g = v.g;
    out.b = v.b;

    // ---- перспективная проекция ----
    // f - фокусное расстояние в пикселях, посчитанное из вертикального
    // FOV - стандартная формула (см. ASSEMBLY.md, "Gpu3D").
    double f = (HEIGHT / 2.0) / std::tan(degToRad(FOV_DEGREES) / 2.0);

    if (vz2 <= 1.0)
    {
        // За камерой/слишком близко - помечаем недопустимой глубиной,
        // drawTriangle() отбросит весь треугольник, если хоть одна из
        // 3 вершин в таком состоянии (см. drawTriangle).
        out.x = 0;
        out.y = 0;
        out.viewZ = -1.0;
        return out;
    }

    out.x = (vx2 / vz2) * f + (WIDTH / 2.0);
    out.y = -(vy2 / vz2) * f + (HEIGHT / 2.0);

    return out;
}

void Gpu3D::drawTriangle()
{
    if (pendingCount < 3)
    {
        status = 1;
        return;
    }

    ScreenVertex sv[3];
    for (int i = 0; i < 3; i++)
    {
        sv[i] = transformAndProject(pendingVertices[i]);
    }

    // Упрощение вместо честного клиппинга (см. ASSEMBLY.md, "Gpu3D") -
    // если хоть одна вершина "за камерой", весь треугольник отбрасывается.
    if (sv[0].viewZ < 0 || sv[1].viewZ < 0 || sv[2].viewZ < 0)
    {
        status = 0;
        return;
    }

    int minX = static_cast<int>(std::floor(std::min({ sv[0].x, sv[1].x, sv[2].x })));
    int maxX = static_cast<int>(std::ceil(std::max({ sv[0].x, sv[1].x, sv[2].x })));
    int minY = static_cast<int>(std::floor(std::min({ sv[0].y, sv[1].y, sv[2].y })));
    int maxY = static_cast<int>(std::ceil(std::max({ sv[0].y, sv[1].y, sv[2].y })));

    minX = std::max(minX, 0);
    minY = std::max(minY, 0);
    maxX = std::min(maxX, WIDTH - 1);
    maxY = std::min(maxY, HEIGHT - 1);

    double x0 = sv[0].x, y0 = sv[0].y;
    double x1 = sv[1].x, y1 = sv[1].y;
    double x2 = sv[2].x, y2 = sv[2].y;

    double area = (x1 - x0) * (y2 - y0) - (x2 - x0) * (y1 - y0);
    if (std::abs(area) < 1e-9)
    {
        status = 0;
        return;   // вырожденный треугольник (нулевая площадь на экране)
    }

    for (int py = minY; py <= maxY; py++)
    {
        for (int px = minX; px <= maxX; px++)
        {
            double sx = px + 0.5;
            double sy = py + 0.5;

            // барицентрические веса через знаковую площадь под-треугольников
            double w0 = ((x1 - sx) * (y2 - sy) - (x2 - sx) * (y1 - sy)) / area;
            double w1 = ((x2 - sx) * (y0 - sy) - (x0 - sx) * (y2 - sy)) / area;
            double w2 = 1.0 - w0 - w1;

            if (w0 < 0 || w1 < 0 || w2 < 0)
            {
                continue;   // вне треугольника
            }

            double depth = w0 * sv[0].viewZ + w1 * sv[1].viewZ + w2 * sv[2].viewZ;

            int pixelIndex = py * WIDTH + px;
            if (depth >= zBuffer[pixelIndex])
            {
                continue;   // уже есть более близкий пиксель
            }

            zBuffer[pixelIndex] = static_cast<float>(depth);
            touchedMask[pixelIndex] = 1;

            int colorIndex = pixelIndex * 3;
            colorBuffer[colorIndex] = static_cast<uint8_t>(w0 * sv[0].r + w1 * sv[1].r + w2 * sv[2].r);
            colorBuffer[colorIndex + 1] = static_cast<uint8_t>(w0 * sv[0].g + w1 * sv[1].g + w2 * sv[2].g);
            colorBuffer[colorIndex + 2] = static_cast<uint8_t>(w0 * sv[0].b + w1 * sv[1].b + w2 * sv[2].b);
        }
    }

    pendingCount = 0;
    status = 0;
}

void Gpu3D::clear()
{
    std::fill(zBuffer.begin(), zBuffer.end(), std::numeric_limits<float>::infinity());
    std::fill(touchedMask.begin(), touchedMask.end(), 0);
    pendingCount = 0;
    status = 0;
}

void Gpu3D::present()
{
    videoCard->setThreeDLayer(colorBuffer.data(), touchedMask.data());
    status = 0;
}
