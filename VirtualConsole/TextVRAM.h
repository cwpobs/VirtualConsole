#pragma once

#include "Device.h"

class TextVRAM : public Device
{
public:

    static const int WIDTH = 80;
    static const int HEIGHT = 25;
    static const int SIZE = WIDTH * HEIGHT;

    TextVRAM();

    uint8_t read(uint32_t address) override;
    void write(uint32_t address, uint8_t value) override;

    void render() const;

private:

    uint8_t data[SIZE];

    void scrollUp();
    void clear();
};
