#include "TextAttr.h"

TextAttr::TextAttr()
{
    for (int i = 0; i < SIZE; i++)
    {
        data[i] = DEFAULT_ATTRIBUTE;
    }
}

uint8_t TextAttr::read(uint32_t address)
{
    if (address == SIZE || address == SIZE + 1)
    {
        // SCROLL/CLEAR - только для записи, чтение возвращает 0
        return 0;
    }

    return data[address];
}

void TextAttr::write(uint32_t address, uint8_t value)
{
    if (address == SIZE)
    {
        // SCROLL - сдвигает экран на одну строку вверх, как у TextVRAM
        scrollUp();
        return;
    }

    if (address == SIZE + 1)
    {
        // CLEAR - сбрасывает всю сетку в цвет по умолчанию
        clear();
        return;
    }

    data[address] = value;
}

uint8_t TextAttr::attributeAt(int index) const
{
    return data[index];
}

void TextAttr::clear()
{
    for (int i = 0; i < SIZE; i++)
    {
        data[i] = DEFAULT_ATTRIBUTE;
    }
}

void TextAttr::scrollUp()
{
    for (int i = 0; i < (HEIGHT - 1) * WIDTH; i++)
    {
        data[i] = data[i + WIDTH];
    }

    for (int i = (HEIGHT - 1) * WIDTH; i < SIZE; i++)
    {
        data[i] = DEFAULT_ATTRIBUTE;
    }
}
