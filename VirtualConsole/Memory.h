#pragma once

#include <cstdint>
#include <vector>

#include "Device.h"

class Memory : public Device
{
public:

    static const uint32_t SIZE = 4 * 1024 * 1024;

    Memory();

    uint8_t read(uint32_t address) override;
    void write(uint32_t address, uint8_t value) override;

private:

    // Хранится в куче, а не как встроенный массив: Memory создаётся
    // как локальная переменная в main(), а 4 МБ на стеке потока
    // (обычно 1 МБ на Windows) переполнили бы его
    std::vector<uint8_t> data;
};
