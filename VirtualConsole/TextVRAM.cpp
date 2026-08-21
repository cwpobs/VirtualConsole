#include "TextVRAM.h"

#include <iostream>

TextVRAM::TextVRAM()
{
    for (int i = 0; i < SIZE; i++)
    {
        data[i] = ' ';
    }
}

uint8_t TextVRAM::read(uint32_t address)
{
    if (address == SIZE)
    {
        // SCROLL - только для записи, чтение возвращает 0
        return 0;
    }

    return data[address];
}

void TextVRAM::write(uint32_t address, uint8_t value)
{
    if (address == SIZE)
    {
        // SCROLL - любая запись сдвигает экран на одну строку вверх
        scrollUp();
        return;
    }

    data[address] = value;
}

void TextVRAM::scrollUp()
{
    for (int i = 0; i < (HEIGHT - 1) * WIDTH; i++)
    {
        data[i] = data[i + WIDTH];
    }

    for (int i = (HEIGHT - 1) * WIDTH; i < SIZE; i++)
    {
        data[i] = ' ';
    }
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
