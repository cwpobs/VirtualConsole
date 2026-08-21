#pragma once

#include "Device.h"

#include <cstdint>
#include <vector>

class VideoCard;

// 3D-ускоритель: вся математика (матрицы модели/камеры, перспективная
// проекция, растеризация с z-буфером) - на стороне C++, тем же
// рассуждением, что и PngLoader/ModLoader - реализовать это в
// ассемблере данного CPU (нет даже нормального умножения, не то что
// тригонометрии) нереально. Ассемблеру видны только команды уровня
// "вот вершина", "нарисуй треугольник", "покажи кадр". См.
// ASSEMBLY.md, раздел "Gpu3D".
//
// Рендеринг идёт во ВНУТРЕННИЙ буфер (свой цветовой буфер + z-буфер +
// маска "затронутых" пикселей) и передаётся в VideoCard целиком одним
// вызовом по команде PRESENT (см. VideoCard::setThreeDLayer) - как
// PngLoader/MapLoader кладут готовый результат одним вызовом, а не
// по регистру на пиксель.
class Gpu3D : public Device
{
public:

    explicit Gpu3D(VideoCard* videoCard);

    uint8_t read(uint32_t address) override;
    void write(uint32_t address, uint8_t value) override;

private:

    static const int WIDTH = 320;
    static const int HEIGHT = 240;

    static const uint32_t REG_VX_LOW = 0;
    static const uint32_t REG_VX_HIGH = 1;
    static const uint32_t REG_VY_LOW = 2;
    static const uint32_t REG_VY_HIGH = 3;
    static const uint32_t REG_VZ_LOW = 4;
    static const uint32_t REG_VZ_HIGH = 5;
    static const uint32_t REG_VR = 6;
    static const uint32_t REG_VG = 7;
    static const uint32_t REG_VB = 8;
    static const uint32_t REG_COMMAND = 9;
    static const uint32_t REG_STATUS = 10;

    static const uint32_t REG_OBJ_X_LOW = 11;
    static const uint32_t REG_OBJ_X_HIGH = 12;
    static const uint32_t REG_OBJ_Y_LOW = 13;
    static const uint32_t REG_OBJ_Y_HIGH = 14;
    static const uint32_t REG_OBJ_Z_LOW = 15;
    static const uint32_t REG_OBJ_Z_HIGH = 16;
    static const uint32_t REG_OBJ_YAW_LOW = 17;
    static const uint32_t REG_OBJ_YAW_HIGH = 18;
    static const uint32_t REG_OBJ_PITCH_LOW = 19;
    static const uint32_t REG_OBJ_PITCH_HIGH = 20;
    static const uint32_t REG_OBJ_ROLL_LOW = 21;
    static const uint32_t REG_OBJ_ROLL_HIGH = 22;

    static const uint32_t REG_CAM_X_LOW = 23;
    static const uint32_t REG_CAM_X_HIGH = 24;
    static const uint32_t REG_CAM_Y_LOW = 25;
    static const uint32_t REG_CAM_Y_HIGH = 26;
    static const uint32_t REG_CAM_Z_LOW = 27;
    static const uint32_t REG_CAM_Z_HIGH = 28;
    static const uint32_t REG_CAM_YAW_LOW = 29;
    static const uint32_t REG_CAM_YAW_HIGH = 30;
    static const uint32_t REG_CAM_PITCH_LOW = 31;
    static const uint32_t REG_CAM_PITCH_HIGH = 32;

    struct Vertex
    {
        double x, y, z;
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
    uint8_t status;

    uint8_t objXLow, objXHigh, objYLow, objYHigh, objZLow, objZHigh;
    uint8_t objYawLow, objYawHigh, objPitchLow, objPitchHigh, objRollLow, objRollHigh;

    uint8_t camXLow, camXHigh, camYLow, camYHigh, camZLow, camZHigh;
    uint8_t camYawLow, camYawHigh, camPitchLow, camPitchHigh;

    Vertex pendingVertices[3];
    int pendingCount;

    std::vector<float> zBuffer;          // WIDTH*HEIGHT
    std::vector<uint8_t> colorBuffer;    // WIDTH*HEIGHT*3
    std::vector<uint8_t> touchedMask;    // WIDTH*HEIGHT

    static int16_t combine(uint8_t low, uint8_t high);

    void submitVertex();
    void drawTriangle();
    void clear();
    void present();

    ScreenVertex transformAndProject(const Vertex& v) const;
};
