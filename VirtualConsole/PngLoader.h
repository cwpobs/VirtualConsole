#pragma once

#include "Device.h"

#include <cstdint>
#include <string>
#include <vector>

class VideoCard;
class Disk;

// Устройство "загрузчик PNG" - декодирует спрайтшит (PNG со сжатием
// zlib/deflate - декодировать такое в ассемблере этого CPU нереально)
// на стороне C++ (через stb_image.h) и вырезает из него квадраты
// 32x32 прямо в видеопамять аппаратных спрайтов VideoCard. Ассемблеру
// видна только команда "загрузи файл" / "вырежи регион в спрайт N" -
// вся работа с форматом PNG спрятана здесь. См. ASSEMBLY.md,
// раздел "PngLoader".
class PngLoader : public Device
{
public:

    // videoCard - куда складывать вырезанные спрайты (см.
    // VideoCard::setSpriteBitmap). diskC - откуда брать ТЕКУЩУЮ папку
    // (Disk::getCurrentPath()) - файл ищется там же, где сейчас "стоит"
    // диск C (меняется командой cd), а не всегда в корне - так
    // запущенная из C/DEMOS программа находит свои же ресурсы рядом
    // с собой.
    PngLoader(VideoCard* videoCard, Disk* diskC);

    uint8_t read(uint32_t address) override;
    void write(uint32_t address, uint8_t value) override;

private:

    static const int CELL_SIZE = 32;   // и спрайты, и тайлы - 32x32

    static const uint32_t REG_NAME_FIRST = 0;
    static const uint32_t REG_NAME_LAST = 11;
    static const uint32_t REG_SRC_X_LOW = 12;
    static const uint32_t REG_SRC_X_HIGH = 13;
    static const uint32_t REG_SRC_Y_LOW = 14;
    static const uint32_t REG_SRC_Y_HIGH = 15;
    static const uint32_t REG_SPRITE_INDEX = 16;
    static const uint32_t REG_COMMAND = 17;
    static const uint32_t REG_STATUS = 18;
    static const uint32_t REG_TILE_INDEX = 19;

    VideoCard* videoCard;
    Disk* diskC;

    uint8_t name[12];
    uint8_t srcXLow, srcXHigh, srcYLow, srcYHigh;
    uint8_t spriteIndex;
    uint8_t status;
    uint8_t tileIndex;

    // Кэш последнего успешно декодированного изображения (RGBA,
    // 4 байта/пиксель) - один LOAD обслуживает много EXTRACT/
    // EXTRACT_TILE без повторного декодирования того же файла.
    std::vector<uint8_t> pixels;
    int imageWidth;
    int imageHeight;

    std::string nameAsString() const;
    uint16_t srcX() const;
    uint16_t srcY() const;

    void load();

    // extractInto - общая логика вырезания квадрата CELL_SIZE и
    // передачи его в VideoCard; extract()/extractTile() - тонкие
    // обёртки, различающиеся только тем, куда кладут результат
    // (спрайт по SPRITE_INDEX или тайл по TILE_INDEX) и какой предел
    // проверяют у индекса (16 спрайтов / 128 тайлов).
    void extractInto(int targetIndex, int indexLimit, bool isTile);
    void extract();
    void extractTile();
};
