#pragma once

#include "Device.h"

class TextAttr;

class TextVRAM : public Device
{
public:

    static const int WIDTH = 80;
    static const int HEIGHT = 25;
    static const int SIZE = WIDTH * HEIGHT;

    TextVRAM();

    uint8_t read(uint32_t address) override;
    void write(uint32_t address, uint8_t value) override;

    // attr - плоскость цветовых атрибутов (см. TextAttr); может быть
    // nullptr, тогда рендерится без цвета (как раньше).
    void render(const TextAttr* attr) const;

private:

    uint8_t data[SIZE];

    void scrollUp();
    void clear();
};
