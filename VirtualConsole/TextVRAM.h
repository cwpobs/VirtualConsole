#pragma once

#include "Device.h"

#include <ostream>

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
    // nullptr, тогда рендерится без цвета (как раньше). out - куда
    // писать кадр - вызывающий сам решает, когда сбрасывать его на
    // экран одним write (см. main.cpp, redraw()) - render() сам по
    // себе flush не делает.
    void render(const TextAttr* attr, std::ostream& out) const;

    // Сырой байт символа по индексу ячейки (0..SIZE-1), без похода
    // через ANSI-render() - нужен VideoConsole, чтобы скопировать кадр
    // в свою память (см. VideoConsole::pushFrame). Аналог
    // TextAttr::attributeAt.
    uint8_t charAt(int index) const;

private:

    uint8_t data[SIZE];

    void scrollUp();
    void clear();
};
