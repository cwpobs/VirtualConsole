#pragma once

#include "Device.h"

#include <cstdint>
#include <vector>

class VideoCard;

// 3D-ускоритель + свет + математический сопроцессор - ОДНО устройство
// (раньше было три: Gpu3D/Light3D/MathUnit - по итогам живого тестирования
// признано неудачным дроблением, см. misty-zooming-bee.md). Вся тяжёлая
// математика (матрицы модели/камеры, перспективная проекция, растеризация
// с z-буфером, тригонометрия/умножение/деление) - на стороне C++, тем же
// рассуждением, что и PngLoader/ModLoader - реализовать это в ассемблере
// данного CPU нереально. Ассемблеру/мини-C видны только команды уровня
// "вот вершина", "нарисуй треугольник"/"нарисуй куб", "посчитай A+B",
// "покажи кадр". См. ASSEMBLY.md, раздел "Gpu3D".
//
// Рендеринг идёт во ВНУТРЕННИЙ буфер (свой цветовой буфер + z-буфер +
// маска "затронутых" пикселей) и передаётся в VideoCard целиком одним
// вызовом по команде PRESENT (см. VideoCard::setThreeDLayer) - как
// PngLoader/MapLoader кладут готовый результат одним вызовом, а не по
// регистру на пиксель.
//
// Адресный диапазон нарочно большой (256 байт, см. main.cpp) - реально
// занято меньше трети; остальное - запас под будущий рост (текстуры,
// доп. источники света) БЕЗ повторной перенумерации регистров - именно
// то, чего не хватило в прошлый раз (Gpu3D/Light3D/MathUnit пришлось
// разносить по трём тесным диапазонам подряд).
class Gpu3D : public Device
{
public:

    explicit Gpu3D(VideoCard* videoCard);

    uint8_t read(uint32_t address) override;
    void write(uint32_t address, uint8_t value) override;

private:

    static const int WIDTH = 320;
    static const int HEIGHT = 240;

    // ---- вершина/цвет/команда ----
    static const uint32_t REG_VX_LOW = 0;
    static const uint32_t REG_VX_HIGH = 1;
    static const uint32_t REG_VY_LOW = 2;
    static const uint32_t REG_VY_HIGH = 3;
    static const uint32_t REG_VZ_LOW = 4;
    static const uint32_t REG_VZ_HIGH = 5;
    static const uint32_t REG_VR = 6;
    static const uint32_t REG_VG = 7;
    static const uint32_t REG_VB = 8;
    static const uint32_t REG_VNX = 9;
    static const uint32_t REG_VNY = 10;
    static const uint32_t REG_VNZ = 11;
    static const uint32_t REG_VU = 12;         // зарезервировано под текстуры
    static const uint32_t REG_VV = 13;         // зарезервировано под текстуры
    static const uint32_t REG_VTEXTURE = 14;   // зарезервировано под текстуры
    static const uint32_t REG_COMMAND = 15;
    static const uint32_t REG_STATUS = 16;
    static const uint32_t REG_CUBE_SIZE_LOW = 17;
    static const uint32_t REG_CUBE_SIZE_HIGH = 18;

    // ---- трансформ объекта/камеры ----
    static const uint32_t REG_OBJ_X_LOW = 19;
    static const uint32_t REG_OBJ_X_HIGH = 20;
    static const uint32_t REG_OBJ_Y_LOW = 21;
    static const uint32_t REG_OBJ_Y_HIGH = 22;
    static const uint32_t REG_OBJ_Z_LOW = 23;
    static const uint32_t REG_OBJ_Z_HIGH = 24;
    static const uint32_t REG_OBJ_YAW_LOW = 25;
    static const uint32_t REG_OBJ_YAW_HIGH = 26;
    static const uint32_t REG_OBJ_PITCH_LOW = 27;
    static const uint32_t REG_OBJ_PITCH_HIGH = 28;
    static const uint32_t REG_OBJ_ROLL_LOW = 29;
    static const uint32_t REG_OBJ_ROLL_HIGH = 30;

    static const uint32_t REG_CAM_X_LOW = 31;
    static const uint32_t REG_CAM_X_HIGH = 32;
    static const uint32_t REG_CAM_Y_LOW = 33;
    static const uint32_t REG_CAM_Y_HIGH = 34;
    static const uint32_t REG_CAM_Z_LOW = 35;
    static const uint32_t REG_CAM_Z_HIGH = 36;
    static const uint32_t REG_CAM_YAW_LOW = 37;
    static const uint32_t REG_CAM_YAW_HIGH = 38;
    static const uint32_t REG_CAM_PITCH_LOW = 39;
    static const uint32_t REG_CAM_PITCH_HIGH = 40;

    // ---- свет (был отдельным устройством Light3D) ----
    static const uint32_t REG_LIGHT_DIR_X = 41;
    static const uint32_t REG_LIGHT_DIR_Y = 42;
    static const uint32_t REG_LIGHT_DIR_Z = 43;
    static const uint32_t REG_LIGHT_R = 44;
    static const uint32_t REG_LIGHT_G = 45;
    static const uint32_t REG_LIGHT_B = 46;
    static const uint32_t REG_AMBIENT = 47;

    // 48-55: зарезервировано (будущий протокол загрузки текстур)

    // ---- математика 16 бит (был отдельным устройством MathUnit) ----
    static const uint32_t REG_MATH_A_LOW = 56;
    static const uint32_t REG_MATH_A_HIGH = 57;
    static const uint32_t REG_MATH_B_LOW = 58;
    static const uint32_t REG_MATH_B_HIGH = 59;
    static const uint32_t REG_MATH_COMMAND = 60;
    static const uint32_t REG_MATH_STATUS = 61;
    static const uint32_t REG_MATH_RESULT_LOW = 62;
    static const uint32_t REG_MATH_RESULT_HIGH = 63;

    // ---- математика 32 бита (новое - "мощнее", см. misty-zooming-bee.md) ----
    static const uint32_t REG_MATH32_A0 = 64;
    static const uint32_t REG_MATH32_A1 = 65;
    static const uint32_t REG_MATH32_A2 = 66;
    static const uint32_t REG_MATH32_A3 = 67;
    static const uint32_t REG_MATH32_B0 = 68;
    static const uint32_t REG_MATH32_B1 = 69;
    static const uint32_t REG_MATH32_B2 = 70;
    static const uint32_t REG_MATH32_B3 = 71;
    static const uint32_t REG_MATH32_COMMAND = 72;
    static const uint32_t REG_MATH32_STATUS = 73;
    static const uint32_t REG_MATH32_RESULT0 = 74;
    static const uint32_t REG_MATH32_RESULT1 = 75;
    static const uint32_t REG_MATH32_RESULT2 = 76;
    static const uint32_t REG_MATH32_RESULT3 = 77;

    struct Vertex
    {
        double x, y, z;
        double nx, ny, nz;   // нормаль (снэпшот VNX/VNY/VNZ в момент SUBMIT_VERTEX)
        uint8_t r, g, b;
    };

    struct ScreenVertex
    {
        double x, y;    // экранные координаты (float - до растеризации)
        double viewZ;   // глубина в пространстве камеры (для z-буфера)
        uint8_t r, g, b;
    };

    VideoCard* videoCard;

    uint8_t vxLow, vxHigh, vyLow, vyHigh, vzLow, vzHigh;
    uint8_t vr, vg, vb;
    uint8_t vnx, vny, vnz;
    uint8_t vu, vv, vtexture;   // зарезервировано, хранится, но не используется
    uint8_t status;
    uint8_t cubeSizeLow, cubeSizeHigh;

    uint8_t objXLow, objXHigh, objYLow, objYHigh, objZLow, objZHigh;
    uint8_t objYawLow, objYawHigh, objPitchLow, objPitchHigh, objRollLow, objRollHigh;

    uint8_t camXLow, camXHigh, camYLow, camYHigh, camZLow, camZHigh;
    uint8_t camYawLow, camYawHigh, camPitchLow, camPitchHigh;

    uint8_t lightDirX, lightDirY, lightDirZ;
    uint8_t lightR, lightG, lightB;
    uint8_t ambient;

    uint8_t mathALow, mathAHigh, mathBLow, mathBHigh;
    uint8_t mathStatus;
    uint8_t mathResultLow, mathResultHigh;

    uint8_t math32A[4], math32B[4];
    uint8_t math32Status;
    uint8_t math32Result[4];

    Vertex pendingVertices[3];
    int pendingCount;

    std::vector<float> zBuffer;          // WIDTH*HEIGHT
    std::vector<uint8_t> colorBuffer;    // WIDTH*HEIGHT*3
    std::vector<uint8_t> touchedMask;    // WIDTH*HEIGHT

    static int16_t combine(uint8_t low, uint8_t high);
    static void split(int16_t value, uint8_t& low, uint8_t& high);
    static double toUnit(uint8_t raw);

    static int32_t combine32(const uint8_t bytes[4]);
    static void split32(int32_t value, uint8_t bytes[4]);

    void submitVertex();
    void drawTriangle();
    void drawCube();
    void clear();
    void present();

    void executeMath16(uint8_t command);
    void executeMath32(uint8_t command);

    ScreenVertex transformAndProject(const Vertex& v) const;
    void rasterizeTriangle(const Vertex (&verts)[3]);
};
