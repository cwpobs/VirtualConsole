#pragma once

#include "Device.h"

#include <cstdint>
#include <string>

class VideoCard;
class Disk;

// Устройство "загрузчик карты" - читает текстовый файл тайловой карты
// с диска "C" и парсит его на стороне C++ (см. ASSEMBLY.md, "MapLoader"
// про формат файла), кладёт результат в VideoCard::setTileMap одним
// вызовом. Как и с PNG, разбор текста в ассемблере этого CPU был бы
// неоправданно громоздким - ассемблеру видна только команда
// "загрузи файл карты". diskC - откуда брать ТЕКУЩУЮ папку (см.
// PngLoader про то же самое).
class MapLoader : public Device
{
public:

    MapLoader(VideoCard* videoCard, Disk* diskC);

    uint8_t read(uint32_t address) override;
    void write(uint32_t address, uint8_t value) override;

private:

    static const uint32_t REG_NAME_FIRST = 0;
    static const uint32_t REG_NAME_LAST = 11;
    static const uint32_t REG_COMMAND = 12;
    static const uint32_t REG_STATUS = 13;

    VideoCard* videoCard;
    Disk* diskC;

    uint8_t name[12];
    uint8_t status;

    std::string nameAsString() const;

    void load();
};
