#include "TextVRAM.h"

#include <iostream>

TextVRAM::TextVRAM()
{
    for (int i = 0; i < SIZE; i++)
    {
        data[i] = ' ';
    }
}

uint8_t TextVRAM::read(uint16_t address)
{
    return data[address];
}

void TextVRAM::write(uint16_t address, uint8_t value)
{
    data[address] = value;
}

void TextVRAM::render() const
{
    for (int y = 0; y < HEIGHT; y++)
    {
        for (int x = 0; x < WIDTH; x++)
        {
            uint8_t c = data[y * WIDTH + x];

            std::cout << (c == 0 ? ' ' : static_cast<char>(c));
        }

        std::cout << "\n";
    }
}
