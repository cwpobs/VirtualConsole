#include "Memory.h"

Memory::Memory()
{
    // При запуске вся память заполнена нулями
    for (uint32_t i = 0; i < SIZE; i++)
    {
        data[i] = 0;
    }
}

uint8_t Memory::read(uint16_t address)
{
    return data[address];
}

void Memory::write(uint16_t address, uint8_t value)
{
    data[address] = value;
}