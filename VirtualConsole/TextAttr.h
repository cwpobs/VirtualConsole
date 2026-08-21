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

    TextAttr();

    uint8_t read(uint32_t address) override;
    void write(uint32_t address, uint8_t value) override;

    uint8_t attributeAt(int index) const;

private:

    uint8_t data[SIZE];

    void scrollUp();
    void clear();
};
