#pragma once

#include <cstdint>

#include "Device.h"

class Memory : public Device
{
public:

    static const uint32_t SIZE = 65536;

    Memory();

    uint8_t read(uint16_t address) override;
    void write(uint16_t address, uint8_t value) override;

private:

    uint8_t data[SIZE];
};