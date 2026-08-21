#pragma once

#include <cstdint>

class Memory
{
public:

    static const uint32_t SIZE = 65536;

    Memory();

    uint8_t read(uint16_t address);
    void write(uint16_t address, uint8_t value);

private:

    uint8_t data[SIZE];
};