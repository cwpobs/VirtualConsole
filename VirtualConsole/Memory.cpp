#include "Memory.h"

Memory::Memory()
    : data(SIZE, 0)
{
}

uint8_t Memory::read(uint32_t address)
{
    return data[address];
}

void Memory::write(uint32_t address, uint8_t value)
{
    data[address] = value;
}
