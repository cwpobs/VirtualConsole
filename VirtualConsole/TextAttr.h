#pragma once

#include "Device.h"

// Плоскость цветовых атрибутов, отдельная от TextVRAM (см.
// ASSEMBLY.md, "TextAttr"). Та же сетка 80x25, что и Text VRAM,
// но хранит не символ, а цвет: младший нибл байта - цвет символа
// (0-15), старший нибл - цвет фона (0-15), классический PC-формат.
// Отдельное устройство, а не встроенное поле TextVRAM, чтобы не
// трогать уже работающие адреса Text VRAM/DebugPort/дисков.
class TextAttr : public Device
{
public:

    static const int WIDTH = 80;
    static const int HEIGHT = 25;
    static const int SIZE = WIDTH * HEIGHT;

    // Цвет по умолчанию - светло-серый (7) на чёрном (0), классика DOS.
    static const uint8_t DEFAULT_ATTRIBUTE = 0x07;

    // Значение старшего нибла (фон) 8-15 - "яркая" половина классической
    // PC-палитры - нигде в этом проекте не используется как настоящий
    // фон (ни в одной .MC/.ASM программе; проверено - везде фон 0/1/7).
    // Значение TRANSPARENT_BG (8) занято под прозрачный фон - см.
    // VideoConsole::rasterize(): для такой ячейки рисуется только сам
    // символ (глиф) нужным цветом, фон не трогается вообще - виден
    // слой VideoCard или то, что уже нарисовано под ним. Как обычный
    // ЦВЕТ СИМВОЛА (в младшем нибле) 8 по-прежнему работает как всегда
    // (тёмно-серый) - особый смысл только у старшего нибла.
    static const uint8_t TRANSPARENT_BG = 8;

    TextAttr();

    uint8_t read(uint32_t address) override;
    void write(uint32_t address, uint8_t value) override;

    uint8_t attributeAt(int index) const;

private:

    uint8_t data[SIZE];

    void scrollUp();
    void clear();
};
