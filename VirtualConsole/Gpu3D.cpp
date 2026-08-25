#include "Gpu3D.h"
#include "VideoCard.h"
#include "Disk.h"

// Только объявления stb_image - реализация (STB_IMAGE_IMPLEMENTATION)
// уже один раз определена в PngLoader.cpp; определить её здесь ЕЩЁ раз
// значило бы получить дублирующиеся символы на этапе линковки (stb -
// однозаголовочная библиотека, реализация должна попасть в бинарник
// ровно один раз, из одной единицы трансляции).
#include "stb_image.h"

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

Gpu3D::Gpu3D(VideoCard* videoCard, Disk* diskC)
    : videoCard(videoCard), diskC(diskC)
{
    vxLow = vxHigh = vyLow = vyHigh = vzLow = vzHigh = 0;
    vr = vg = vb = 0;
    vnx = vny = vnz = 0;
    vu = vv = vtexture = 0;
    status = 0;
    cubeSizeLow = cubeSizeHigh = 0;

    objXLow = objXHigh = objYLow = objYHigh = objZLow = objZHigh = 0;
    objYawLow = objYawHigh = objPitchLow = objPitchHigh = objRollLow = objRollHigh = 0;

    camXLow = camXHigh = camYLow = camYHigh = camZLow = camZHigh = 0;
    camYawLow = camYawHigh = camPitchLow = camPitchHigh = 0;

    lightDirX = 0;
    lightDirY = 0;
    lightDirZ = static_cast<uint8_t>(static_cast<int8_t>(-100)); // по умолчанию светит вдоль -Z
    lightR = lightG = lightB = 255;
    ambient = 60;

    mathALow = mathAHigh = mathBLow = mathBHigh = 0;
    mathStatus = 0;
    mathResultLow = mathResultHigh = 0;

    for (int i = 0; i < 4; i++) { math32A[i] = math32B[i] = math32Result[i] = 0; }
    math32Status = 0;

    for (int i = 0; i < 12; i++) { texName[i] = 0; }
    texSrcXLow = texSrcXHigh = texSrcYLow = texSrcYHigh = 0;
    texSlot = 0;
    texStatus = 0;
    texSourceWidth = 0;
    texSourceHeight = 0;
    textureSlots.assign(static_cast<size_t>(TEXTURE_SLOTS) * TEX_SIZE * TEX_SIZE * 3, 0);

    pendingCount = 0;

    zBuffer.assign(WIDTH * HEIGHT, std::numeric_limits<float>::infinity());
    colorBuffer.assign(WIDTH * HEIGHT * 3, 0);
    touchedMask.assign(WIDTH * HEIGHT, 0);
}

int16_t Gpu3D::combine(uint8_t low, uint8_t high)
{
    return static_cast<int16_t>(static_cast<uint16_t>(low) | (static_cast<uint16_t>(high) << 8));
}

void Gpu3D::split(int16_t value, uint8_t& low, uint8_t& high)
{
    uint16_t bits = static_cast<uint16_t>(value);
    low = static_cast<uint8_t>(bits & 0xFF);
    high = static_cast<uint8_t>((bits >> 8) & 0xFF);
}

double Gpu3D::toUnit(uint8_t raw)
{
    return static_cast<double>(static_cast<int8_t>(raw)) / 100.0;
}

int32_t Gpu3D::combine32(const uint8_t bytes[4])
{
    return static_cast<int32_t>(
        static_cast<uint32_t>(bytes[0]) |
        (static_cast<uint32_t>(bytes[1]) << 8) |
        (static_cast<uint32_t>(bytes[2]) << 16) |
        (static_cast<uint32_t>(bytes[3]) << 24));
}

void Gpu3D::split32(int32_t value, uint8_t bytes[4])
{
    uint32_t bits = static_cast<uint32_t>(value);
    bytes[0] = static_cast<uint8_t>(bits & 0xFF);
    bytes[1] = static_cast<uint8_t>((bits >> 8) & 0xFF);
    bytes[2] = static_cast<uint8_t>((bits >> 16) & 0xFF);
    bytes[3] = static_cast<uint8_t>((bits >> 24) & 0xFF);
}

uint8_t Gpu3D::read(uint32_t address)
{
    if (address >= REG_TEX_NAME_FIRST && address <= REG_TEX_NAME_LAST)
    {
        return texName[address - REG_TEX_NAME_FIRST];
    }

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
    case REG_VNX: return vnx;
    case REG_VNY: return vny;
    case REG_VNZ: return vnz;
    case REG_VU: return vu;
    case REG_VV: return vv;
    case REG_VTEXTURE: return vtexture;
    case REG_STATUS: return status;
    case REG_CUBE_SIZE_LOW: return cubeSizeLow;
    case REG_CUBE_SIZE_HIGH: return cubeSizeHigh;

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

    case REG_LIGHT_DIR_X: return lightDirX;
    case REG_LIGHT_DIR_Y: return lightDirY;
    case REG_LIGHT_DIR_Z: return lightDirZ;
    case REG_LIGHT_R: return lightR;
    case REG_LIGHT_G: return lightG;
    case REG_LIGHT_B: return lightB;
    case REG_AMBIENT: return ambient;

    case REG_MATH_A_LOW: return mathALow;
    case REG_MATH_A_HIGH: return mathAHigh;
    case REG_MATH_B_LOW: return mathBLow;
    case REG_MATH_B_HIGH: return mathBHigh;
    case REG_MATH_STATUS: return mathStatus;
    case REG_MATH_RESULT_LOW: return mathResultLow;
    case REG_MATH_RESULT_HIGH: return mathResultHigh;

    case REG_MATH32_A0: return math32A[0];
    case REG_MATH32_A1: return math32A[1];
    case REG_MATH32_A2: return math32A[2];
    case REG_MATH32_A3: return math32A[3];
    case REG_MATH32_B0: return math32B[0];
    case REG_MATH32_B1: return math32B[1];
    case REG_MATH32_B2: return math32B[2];
    case REG_MATH32_B3: return math32B[3];
    case REG_MATH32_STATUS: return math32Status;
    case REG_MATH32_RESULT0: return math32Result[0];
    case REG_MATH32_RESULT1: return math32Result[1];
    case REG_MATH32_RESULT2: return math32Result[2];
    case REG_MATH32_RESULT3: return math32Result[3];

    case REG_TEX_SRC_X_LOW: return texSrcXLow;
    case REG_TEX_SRC_X_HIGH: return texSrcXHigh;
    case REG_TEX_SRC_Y_LOW: return texSrcYLow;
    case REG_TEX_SRC_Y_HIGH: return texSrcYHigh;
    case REG_TEX_SLOT: return texSlot;
    case REG_TEX_STATUS: return texStatus;

    default: return 0;
    }
}

void Gpu3D::write(uint32_t address, uint8_t value)
{
    if (address >= REG_TEX_NAME_FIRST && address <= REG_TEX_NAME_LAST)
    {
        texName[address - REG_TEX_NAME_FIRST] = value;
        return;
    }

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
    case REG_VNX: vnx = value; return;
    case REG_VNY: vny = value; return;
    case REG_VNZ: vnz = value; return;
    case REG_VU: vu = value; return;
    case REG_VV: vv = value; return;
    case REG_VTEXTURE: vtexture = value; return;
    case REG_CUBE_SIZE_LOW: cubeSizeLow = value; return;
    case REG_CUBE_SIZE_HIGH: cubeSizeHigh = value; return;

    case REG_COMMAND:
        switch (value)
        {
        case 1: submitVertex(); break;
        case 2: drawTriangle(); break;
        case 3: clear(); break;
        case 4: present(); break;
        case 5: drawCube(); break;
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

    case REG_LIGHT_DIR_X: lightDirX = value; return;
    case REG_LIGHT_DIR_Y: lightDirY = value; return;
    case REG_LIGHT_DIR_Z: lightDirZ = value; return;
    case REG_LIGHT_R: lightR = value; return;
    case REG_LIGHT_G: lightG = value; return;
    case REG_LIGHT_B: lightB = value; return;
    case REG_AMBIENT: ambient = value; return;

    case REG_MATH_A_LOW: mathALow = value; return;
    case REG_MATH_A_HIGH: mathAHigh = value; return;
    case REG_MATH_B_LOW: mathBLow = value; return;
    case REG_MATH_B_HIGH: mathBHigh = value; return;
    case REG_MATH_COMMAND: executeMath16(value); return;

    case REG_MATH32_A0: math32A[0] = value; return;
    case REG_MATH32_A1: math32A[1] = value; return;
    case REG_MATH32_A2: math32A[2] = value; return;
    case REG_MATH32_A3: math32A[3] = value; return;
    case REG_MATH32_B0: math32B[0] = value; return;
    case REG_MATH32_B1: math32B[1] = value; return;
    case REG_MATH32_B2: math32B[2] = value; return;
    case REG_MATH32_B3: math32B[3] = value; return;
    case REG_MATH32_COMMAND: executeMath32(value); return;

    case REG_TEX_SRC_X_LOW: texSrcXLow = value; return;
    case REG_TEX_SRC_X_HIGH: texSrcXHigh = value; return;
    case REG_TEX_SRC_Y_LOW: texSrcYLow = value; return;
    case REG_TEX_SRC_Y_HIGH: texSrcYHigh = value; return;
    case REG_TEX_SLOT: texSlot = value; return;

    case REG_TEX_COMMAND:
        switch (value)
        {
        case 1: loadTexture(); break;
        case 2: extractTexture(); break;
        default: break;
        }
        return;

    default:
        return;
    }
}

void Gpu3D::executeMath16(uint8_t command)
{
    int16_t a = combine(mathALow, mathAHigh);
    int16_t b = combine(mathBLow, mathBHigh);

    mathStatus = 0;
    int16_t result = 0;

    switch (command)
    {
    case 1: result = static_cast<int16_t>(static_cast<uint16_t>(a) + static_cast<uint16_t>(b)); break; // ADD
    case 2: result = static_cast<int16_t>(static_cast<uint16_t>(a) - static_cast<uint16_t>(b)); break; // SUB
    case 3: result = static_cast<int16_t>(static_cast<uint16_t>(a * b)); break; // MUL

    case 4: // DIV
        if (b == 0) { mathStatus = 1; result = 0; }
        else { result = static_cast<int16_t>(a / b); }
        break;

    case 5: // SIN - a - угол в градусах, результат *100 (100 = 1.0)
        result = static_cast<int16_t>(std::lround(std::sin(degToRad(a)) * 100.0));
        break;

    case 6: // COS
        result = static_cast<int16_t>(std::lround(std::cos(degToRad(a)) * 100.0));
        break;

    case 7: // SQRT
        if (a < 0) { mathStatus = 1; result = 0; }
        else { result = static_cast<int16_t>(std::lround(std::sqrt(static_cast<double>(a)))); }
        break;

    default:
        break;
    }

    split(result, mathResultLow, mathResultHigh);
}

void Gpu3D::executeMath32(uint8_t command)
{
    int32_t a = combine32(math32A);
    int32_t b = combine32(math32B);

    math32Status = 0;
    int32_t result = 0;

    switch (command)
    {
    case 1: result = static_cast<int32_t>(static_cast<uint32_t>(a) + static_cast<uint32_t>(b)); break; // ADD
    case 2: result = static_cast<int32_t>(static_cast<uint32_t>(a) - static_cast<uint32_t>(b)); break; // SUB
    case 3: result = static_cast<int32_t>(static_cast<uint32_t>(a) * static_cast<uint32_t>(b)); break; // MUL

    case 4: // DIV
        if (b == 0) { math32Status = 1; result = 0; }
        else { result = a / b; }
        break;

    case 5: // SQRT - целочисленный квадратный корень (без тригонометрии - 32 бита нужны для позиций/дистанций, не углов)
        if (a < 0) { math32Status = 1; result = 0; }
        else { result = static_cast<int32_t>(std::llround(std::sqrt(static_cast<double>(a)))); }
        break;

    default:
        break;
    }

    split32(result, math32Result);
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
    pendingVertices[slot].nx = toUnit(vnx);
    pendingVertices[slot].ny = toUnit(vny);
    pendingVertices[slot].nz = toUnit(vnz);
    pendingVertices[slot].u = vu / 255.0;
    pendingVertices[slot].v = vv / 255.0;
    pendingVertices[slot].textureSlot = vtexture;
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

    // ---- та же модельная матрица (roll -> pitch -> yaw), но БЕЗ переноса -
    // применяется к нормали, чтобы получить мировую нормаль для освещения ----

    double nx = v.nx, ny = v.ny, nz = v.nz;

    double nx1 = nx * std::cos(roll) - ny * std::sin(roll);
    double ny1 = nx * std::sin(roll) + ny * std::cos(roll);
    double nz1 = nz;

    double ny2 = ny1 * std::cos(pitch) - nz1 * std::sin(pitch);
    double nz2 = ny1 * std::sin(pitch) + nz1 * std::cos(pitch);
    double nx2 = nx1;

    double worldNx = nx2 * std::cos(yaw) + nz2 * std::sin(yaw);
    double worldNz = -nx2 * std::sin(yaw) + nz2 * std::cos(yaw);
    double worldNy = ny2;

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

    // ---- освещение (Gouraud - считается один раз на вершину, дальше
    // просто интерполируется по треугольнику в rasterizeTriangle, как и
    // раньше с "сырым" цветом вершины) - направленный свет + фоновая
    // засветка ----

    double lightDirXu = toUnit(lightDirX);
    double lightDirYu = toUnit(lightDirY);
    double lightDirZu = toUnit(lightDirZ);
    double lightLen = std::sqrt(lightDirXu * lightDirXu + lightDirYu * lightDirYu + lightDirZu * lightDirZu);

    double diffuseFactor = 0.0;
    if (lightLen > 1e-6)
    {
        double dot = (worldNx * lightDirXu + worldNy * lightDirYu + worldNz * lightDirZu) / lightLen;
        diffuseFactor = std::max(0.0, dot);
    }

    double ambientFactor = ambient / 255.0;

    auto brightnessOf = [&](uint8_t lightChannel) -> double
    {
        return ambientFactor + (lightChannel / 255.0) * diffuseFactor;
    };

    auto lit = [&](uint8_t base, double brightness) -> uint8_t
    {
        double value = base * brightness;
        return static_cast<uint8_t>(std::min(255.0, std::max(0.0, value)));
    };

    ScreenVertex out;
    out.viewZ = vz2;
    out.u = v.u;
    out.v = v.v;
    out.litR = brightnessOf(lightR);
    out.litG = brightnessOf(lightG);
    out.litB = brightnessOf(lightB);
    out.r = lit(v.r, out.litR);
    out.g = lit(v.g, out.litG);
    out.b = lit(v.b, out.litB);

    // ---- перспективная проекция ----
    // f - фокусное расстояние в пикселях, посчитанное из вертикального
    // FOV - стандартная формула (см. ASSEMBLY.md, "Gpu3D").
    double f = (HEIGHT / 2.0) / std::tan(degToRad(FOV_DEGREES) / 2.0);

    if (vz2 <= 1.0)
    {
        // За камерой/слишком близко - помечаем недопустимой глубиной,
        // rasterizeTriangle() отбросит весь треугольник, если хоть одна
        // из 3 вершин в таком состоянии.
        out.x = 0;
        out.y = 0;
        out.viewZ = -1.0;
        return out;
    }

    out.x = (vx2 / vz2) * f + (WIDTH / 2.0);
    out.y = -(vy2 / vz2) * f + (HEIGHT / 2.0);

    return out;
}

void Gpu3D::rasterizeTriangle(const Vertex (&verts)[3])
{
    ScreenVertex sv[3];
    for (int i = 0; i < 3; i++)
    {
        sv[i] = transformAndProject(verts[i]);
    }

    // Текстура не варьируется по вершинам одного треугольника на
    // практике (весь треугольник либо текстурирован одной текстурой,
    // либо нет) - берём с первой вершины, интерполировать незачем.
    int textureSlot = verts[0].textureSlot;
    const uint8_t* texture = nullptr;

    if (textureSlot >= 1 && textureSlot <= TEXTURE_SLOTS)
    {
        texture = &textureSlots[static_cast<size_t>(textureSlot - 1) * TEX_SIZE * TEX_SIZE * 3];
    }

    // Упрощение вместо честного клиппинга (см. ASSEMBLY.md, "Gpu3D") -
    // если хоть одна вершина "за камерой", весь треугольник отбрасывается.
    if (sv[0].viewZ < 0 || sv[1].viewZ < 0 || sv[2].viewZ < 0)
    {
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

            if (texture != nullptr)
            {
                double u = w0 * sv[0].u + w1 * sv[1].u + w2 * sv[2].u;
                double v = w0 * sv[0].v + w1 * sv[1].v + w2 * sv[2].v;
                double litR = w0 * sv[0].litR + w1 * sv[1].litR + w2 * sv[2].litR;
                double litG = w0 * sv[0].litG + w1 * sv[1].litG + w2 * sv[2].litG;
                double litB = w0 * sv[0].litB + w1 * sv[1].litB + w2 * sv[2].litB;

                int tx = std::min(std::max(static_cast<int>(u * (TEX_SIZE - 1)), 0), TEX_SIZE - 1);
                int ty = std::min(std::max(static_cast<int>(v * (TEX_SIZE - 1)), 0), TEX_SIZE - 1);
                int texelIndex = (ty * TEX_SIZE + tx) * 3;

                auto sample = [&](int channel, double brightness) -> uint8_t
                {
                    double value = texture[texelIndex + channel] * brightness;
                    return static_cast<uint8_t>(std::min(255.0, std::max(0.0, value)));
                };

                colorBuffer[colorIndex] = sample(0, litR);
                colorBuffer[colorIndex + 1] = sample(1, litG);
                colorBuffer[colorIndex + 2] = sample(2, litB);
            }
            else
            {
                colorBuffer[colorIndex] = static_cast<uint8_t>(w0 * sv[0].r + w1 * sv[1].r + w2 * sv[2].r);
                colorBuffer[colorIndex + 1] = static_cast<uint8_t>(w0 * sv[0].g + w1 * sv[1].g + w2 * sv[2].g);
                colorBuffer[colorIndex + 2] = static_cast<uint8_t>(w0 * sv[0].b + w1 * sv[1].b + w2 * sv[2].b);
            }
        }
    }
}

void Gpu3D::drawTriangle()
{
    if (pendingCount < 3)
    {
        status = 1;
        return;
    }

    rasterizeTriangle(pendingVertices);

    pendingCount = 0;
    status = 0;
}

void Gpu3D::drawCube()
{
    // Аппаратный примитив "нарисуй куб": вместо 36 SUBMIT_VERTEX (12
    // треугольников по 3 вершины, ~13 poke() на вершину с CPU) вызывающий
    // код шлёт всего центр/размер/цвет (VX/VY/VZ/CUBE_SIZE/VR/VG/VB) -
    // ~12 poke() суммарно - а все 8 вершин и 12 треугольников с
    // правильными осевыми нормалями строит и растеризует C++ здесь,
    // переиспользуя тот же rasterizeTriangle(), что и обычный
    // DRAW_TRIANGLE (см. misty-zooming-bee.md про то, почему это было
    // главной причиной тормозов демки с полом из кубов). Не трогает
    // pendingVertices/pendingCount - можно мешать DRAW_CUBE и обычные
    // SUBMIT_VERTEX/DRAW_TRIANGLE в одном кадре.

    double cx = combine(vxLow, vxHigh);
    double cy = combine(vyLow, vyHigh);
    double cz = combine(vzLow, vzHigh);
    double half = combine(cubeSizeLow, cubeSizeHigh);

    double xMin = cx - half, xMax = cx + half;
    double yMin = cy - half, yMax = cy + half;
    double zMin = cz - half, zMax = cz + half;

    // Те же комбинации min/max по осям на угол, что раньше собирались
    // вручную в мини-C (C/DEV/LIB/GEOM3D.MC, emit_corner) - v0..v7.
    double cxs[8] = { xMin, xMax, xMax, xMin, xMin, xMax, xMax, xMin };
    double cys[8] = { yMin, yMin, yMax, yMax, yMin, yMin, yMax, yMax };
    double czs[8] = { zMin, zMin, zMin, zMin, zMax, zMax, zMax, zMax };

    auto corner = [&](int id) -> Vertex
    {
        Vertex v;
        v.x = cxs[id]; v.y = cys[id]; v.z = czs[id];
        v.nx = v.ny = v.nz = 0;
        v.u = v.v = 0;
        v.textureSlot = vtexture;   // одна текстура на весь куб (как сейчас один цвет)
        v.r = vr; v.g = vg; v.b = vb;
        return v;
    };

    auto withNormal = [](Vertex v, double nx, double ny, double nz) -> Vertex
    {
        v.nx = nx; v.ny = ny; v.nz = nz;
        return v;
    };

    auto withUV = [](Vertex v, double u, double vv) -> Vertex
    {
        v.u = u; v.v = vv;
        return v;
    };

    // Развёртка UV на грань - каждая грань как квад (0,0)-(1,0)-(1,1)-(0,1),
    // разрезанный на два треугольника (p0,p1,p2)/(p0,p2,p3) - тот же
    // порядок углов, что уже используется ниже для позиции/нормали,
    // поэтому UV просто идёт позиционно по вызовам face().
    auto face = [&](int a, int b, int c, double nx, double ny, double nz,
                     double ua, double va, double ub, double vb, double uc, double vcUv)
    {
        Vertex tri[3] =
        {
            withUV(withNormal(corner(a), nx, ny, nz), ua, va),
            withUV(withNormal(corner(b), nx, ny, nz), ub, vb),
            withUV(withNormal(corner(c), nx, ny, nz), uc, vcUv),
        };
        rasterizeTriangle(tri);
    };

    face(0, 1, 2, 0, 0, -1, 0, 0, 1, 0, 1, 1);   // -Z
    face(0, 2, 3, 0, 0, -1, 0, 0, 1, 1, 0, 1);
    face(4, 5, 6, 0, 0, 1, 0, 0, 1, 0, 1, 1);    // +Z
    face(4, 6, 7, 0, 0, 1, 0, 0, 1, 1, 0, 1);
    face(0, 1, 5, 0, -1, 0, 0, 0, 1, 0, 1, 1);   // -Y
    face(0, 5, 4, 0, -1, 0, 0, 0, 1, 1, 0, 1);
    face(3, 2, 6, 0, 1, 0, 0, 0, 1, 0, 1, 1);    // +Y
    face(3, 6, 7, 0, 1, 0, 0, 0, 1, 1, 0, 1);
    face(0, 4, 7, -1, 0, 0, 0, 0, 1, 0, 1, 1);   // -X
    face(0, 7, 3, -1, 0, 0, 0, 0, 1, 1, 0, 1);
    face(1, 2, 6, 1, 0, 0, 0, 0, 1, 0, 1, 1);    // +X
    face(1, 6, 5, 1, 0, 0, 0, 0, 1, 1, 0, 1);

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

std::string Gpu3D::texNameAsString() const
{
    std::string result;

    for (int i = 0; i < 12 && texName[i] != 0; i++)
    {
        result += static_cast<char>(texName[i]);
    }

    return result;
}

void Gpu3D::loadTexture()
{
    // Тот же протокол, что у PngLoader::load() - lastExecDisk см. там же.
    Disk* activeDisk = (Disk::lastExecDisk != nullptr) ? Disk::lastExecDisk : diskC;
    std::string path = (activeDisk->getCurrentPath() / texNameAsString()).string();

    int width = 0;
    int height = 0;
    int channels = 0;

    unsigned char* data = stbi_load(path.c_str(), &width, &height, &channels, 4);

    if (data == nullptr)
    {
        texStatus = 1;
        texSourcePixels.clear();
        texSourceWidth = 0;
        texSourceHeight = 0;
        return;
    }

    texSourcePixels.assign(data, data + (static_cast<size_t>(width) * height * 4));
    stbi_image_free(data);

    texSourceWidth = width;
    texSourceHeight = height;
    texStatus = 0;
}

void Gpu3D::extractTexture()
{
    int slot = texSlot;

    if (slot < 1 || slot > TEXTURE_SLOTS)
    {
        texStatus = 3;
        return;
    }

    if (texSourcePixels.empty())
    {
        texStatus = 1;
        return;
    }

    int x = combine(texSrcXLow, texSrcXHigh);
    int y = combine(texSrcYLow, texSrcYHigh);

    if (x < 0 || y < 0 || x + TEX_SIZE > texSourceWidth || y + TEX_SIZE > texSourceHeight)
    {
        texStatus = 2;
        return;
    }

    uint8_t* dst = &textureSlots[static_cast<size_t>(slot - 1) * TEX_SIZE * TEX_SIZE * 3];

    for (int sy = 0; sy < TEX_SIZE; sy++)
    {
        for (int sx = 0; sx < TEX_SIZE; sx++)
        {
            size_t srcIndex = (static_cast<size_t>(y + sy) * texSourceWidth + (x + sx)) * 4;
            uint8_t r = texSourcePixels[srcIndex];
            uint8_t g = texSourcePixels[srcIndex + 1];
            uint8_t b = texSourcePixels[srcIndex + 2];
            uint8_t a = texSourcePixels[srcIndex + 3];

            int dstIndex = (sy * TEX_SIZE + sx) * 3;

            if (a < 128)
            {
                // Прозрачный пиксель PNG - тот же цвет-ключ, что у
                // PngLoader::extractInto (см. ASSEMBLY.md, "Аппаратные
                // спрайты") - для куба вряд ли пригодится, но
                // реализуется бесплатно тем же кодом.
                dst[dstIndex] = 255;
                dst[dstIndex + 1] = 0;
                dst[dstIndex + 2] = 255;
            }
            else
            {
                dst[dstIndex] = r;
                dst[dstIndex + 1] = g;
                dst[dstIndex + 2] = b;
            }
        }
    }

    texStatus = 0;
}
