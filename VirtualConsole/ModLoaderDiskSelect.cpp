#include "ModLoaderDiskSelect.h"

uint8_t ModLoaderDiskSelect::read(uint32_t /*address*/)
{
    return value;
}

void ModLoaderDiskSelect::write(uint32_t /*address*/, uint8_t v)
{
    value = v;
}
