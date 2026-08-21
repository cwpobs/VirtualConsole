#pragma once

#include "Device.h"

#include <cstdint>
#include <string>

class SoundCard;

// Устройство "загрузчик MOD" - читает и разбирает трекерный .mod-файл
// (см. ASSEMBLY.md, "ModLoader" про формат) на стороне C++ - парсинг
// бинарного формата с секвенсором в ассемблере этого CPU так же
// нереален, как разбор PNG (см. PngLoader) - и кладёт готовую песню
// в SoundCard одним вызовом.
class ModLoader : public Device
{
public:

    // soundCard - куда положить разобранную песню (см.
    // SoundCard::loadSong). Читает файлы из папки "C" (без
    // поддиректорий - v1, как Disk/PngLoader/MapLoader).
    explicit ModLoader(SoundCard* soundCard);

    uint8_t read(uint32_t address) override;
    void write(uint32_t address, uint8_t value) override;

private:

    static const uint32_t REG_NAME_FIRST = 0;
    static const uint32_t REG_NAME_LAST = 31;   // 32 байта - не 12, как у
                                                 // Disk/PngLoader/MapLoader:
                                                 // .mod-имена (например
                                                 // "space_debris.mod") не
                                                 // укладываются в 8.3
    static const uint32_t REG_COMMAND = 32;
    static const uint32_t REG_STATUS = 33;

    SoundCard* soundCard;
    std::string basePath;

    uint8_t name[32];
    uint8_t status;

    std::string nameAsString() const;

    void load();
};
