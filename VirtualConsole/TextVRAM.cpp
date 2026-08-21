#include "TextVRAM.h"
#include "TextAttr.h"

#include <iostream>

// Кодовая страница CP866 ("альтернативная ГОСТ") - классическая
// DOS-кодировка для русского: байты 0x80-0xFF дают кириллицу и
// псевдографику (рамки/полутона/блоки). Байты 0x00-0x7F - обычный
// ASCII, тождественное отображение, отдельной таблицы не нужно.
// Ячейка VRAM остаётся 1 байтом, как и была - в UTF-8 кодовая точка
// переводится только здесь, в момент вывода на экран.
static const char32_t CP866_HIGH[128] =
{
    0x0410, 0x0411, 0x0412, 0x0413, 0x0414, 0x0415, 0x0416, 0x0417, // 80-87 А-З
    0x0418, 0x0419, 0x041A, 0x041B, 0x041C, 0x041D, 0x041E, 0x041F, // 88-8F И-П
    0x0420, 0x0421, 0x0422, 0x0423, 0x0424, 0x0425, 0x0426, 0x0427, // 90-97 Р-Ч
    0x0428, 0x0429, 0x042A, 0x042B, 0x042C, 0x042D, 0x042E, 0x042F, // 98-9F Ш-Я
    0x0430, 0x0431, 0x0432, 0x0433, 0x0434, 0x0435, 0x0436, 0x0437, // A0-A7 а-з
    0x0438, 0x0439, 0x043A, 0x043B, 0x043C, 0x043D, 0x043E, 0x043F, // A8-AF и-п
    0x2591, 0x2592, 0x2593, 0x2502, 0x2524, 0x2561, 0x2562, 0x2556, // B0-B7 псевдографика
    0x2555, 0x2563, 0x2551, 0x2557, 0x255D, 0x255C, 0x255B, 0x2510, // B8-BF
    0x2514, 0x2534, 0x252C, 0x251C, 0x2500, 0x253C, 0x255E, 0x255F, // C0-C7
    0x255A, 0x2554, 0x2569, 0x2566, 0x2560, 0x2550, 0x256C, 0x2567, // C8-CF
    0x2568, 0x2564, 0x2565, 0x2559, 0x2558, 0x2552, 0x2553, 0x256B, // D0-D7
    0x256A, 0x2518, 0x250C, 0x2588, 0x2584, 0x258C, 0x2590, 0x2580, // D8-DF
    0x0440, 0x0441, 0x0442, 0x0443, 0x0444, 0x0445, 0x0446, 0x0447, // E0-E7 р-ч
    0x0448, 0x0449, 0x044A, 0x044B, 0x044C, 0x044D, 0x044E, 0x044F, // E8-EF ш-я
    0x0401, 0x0451, 0x0404, 0x0454, 0x0407, 0x0457, 0x040E, 0x045E, // F0-F7 Ё,ё,Є,є,Ї,ї,Ў,ў
    0x00B0, 0x2219, 0x00B7, 0x221A, 0x2116, 0x00A4, 0x25A0, 0x00A0, // F8-FF °∙·√№¤■(nbsp)
};

static char32_t codepointFor(uint8_t byte)
{
    if (byte < 0x80)
    {
        return byte;
    }

    return CP866_HIGH[byte - 0x80];
}

static void writeUtf8(std::ostream& out, char32_t codepoint)
{
    if (codepoint < 0x80)
    {
        out << static_cast<char>(codepoint);
    }
    else if (codepoint < 0x800)
    {
        out << static_cast<char>(0xC0 | (codepoint >> 6));
        out << static_cast<char>(0x80 | (codepoint & 0x3F));
    }
    else
    {
        out << static_cast<char>(0xE0 | (codepoint >> 12));
        out << static_cast<char>(0x80 | ((codepoint >> 6) & 0x3F));
        out << static_cast<char>(0x80 | (codepoint & 0x3F));
    }
}

TextVRAM::TextVRAM()
{
    for (int i = 0; i < SIZE; i++)
    {
        data[i] = ' ';
    }
}

uint8_t TextVRAM::read(uint32_t address)
{
    if (address == SIZE || address == SIZE + 1)
    {
        // SCROLL/CLEAR - только для записи, чтение возвращает 0
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

    if (address == SIZE + 1)
    {
        // CLEAR - любая запись заполняет весь экран пробелами
        clear();
        return;
    }

    data[address] = value;
}

void TextVRAM::clear()
{
    for (int i = 0; i < SIZE; i++)
    {
        data[i] = ' ';
    }
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

static void writeAnsiColor(std::ostream& out, uint8_t attribute)
{
    int fg = attribute & 0x0F;
    int bg = (attribute >> 4) & 0x0F;

    int fgCode = (fg < 8) ? (30 + fg) : (90 + (fg - 8));
    int bgCode = (bg < 8) ? (40 + bg) : (100 + (bg - 8));

    out << "\x1b[" << fgCode << ";" << bgCode << "m";
}

void TextVRAM::render(const TextAttr* attr) const
{
    int lastAttribute = -1;

    for (int y = 0; y < HEIGHT; y++)
    {
        for (int x = 0; x < WIDTH; x++)
        {
            int index = y * WIDTH + x;
            uint8_t c = data[index];

            if (attr != nullptr)
            {
                int attribute = attr->attributeAt(index);

                if (attribute != lastAttribute)
                {
                    writeAnsiColor(std::cout, static_cast<uint8_t>(attribute));
                    lastAttribute = attribute;
                }
            }

            if (c == 0)
            {
                std::cout << ' ';
            }
            else
            {
                writeUtf8(std::cout, codepointFor(c));
            }
        }

        std::cout << "\n";
    }

    if (attr != nullptr)
    {
        // Сброс цвета в конце кадра - иначе он "утекает" в
        // диагностический дамп/остальной вывод консоли после HLT
        std::cout << "\x1b[0m";
    }
}
