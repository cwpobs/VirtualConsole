#include "ModLoader.h"
#include "SoundCard.h"
#include "Disk.h"
#include "ModLoaderDiskSelect.h"

#include <algorithm>
#include <fstream>
#include <vector>

ModLoader::ModLoader(SoundCard* soundCard, Disk* diskC, Disk* diskD, ModLoaderDiskSelect* diskSelect)
    : soundCard(soundCard), diskC(diskC), diskD(diskD), diskSelect(diskSelect)
{
    for (int i = 0; i < 32; i++)
    {
        name[i] = 0;
    }

    status = 0;
}

std::string ModLoader::nameAsString() const
{
    std::string result;

    for (int i = 0; i < 32 && name[i] != 0; i++)
    {
        result += static_cast<char>(name[i]);
    }

    return result;
}

uint8_t ModLoader::read(uint32_t address)
{
    if (address <= REG_NAME_LAST)
    {
        return name[address];
    }

    if (address == REG_STATUS)
    {
        return status;
    }

    return 0;
}

void ModLoader::write(uint32_t address, uint8_t value)
{
    if (address <= REG_NAME_LAST)
    {
        name[address] = value;
        return;
    }

    if (address == REG_COMMAND && value == 1)
    {
        load();
    }
}

namespace
{
    uint16_t readBE16(const std::vector<uint8_t>& data, size_t offset)
    {
        return (static_cast<uint16_t>(data[offset]) << 8) | data[offset + 1];
    }
}

void ModLoader::load()
{
    // diskSelect (см. ModLoaderDiskSelect.h) - явный выбор диска, нужен
    // плейлисту (треки на разных дисках в одном play.lst - см.
    // ASSEMBLY.md, "ModLoader"/PLAYER.MC): 1=C, 2=D. 0 (значение по
    // умолчанию, никогда не тронутое MODLOADER_DISK_SELECT) - старое
    // поведение без изменений: lastExecDisk - какой диск реально
    // запустил (через exec) текущую выполняющуюся программу - см.
    // Disk.h. До первого exec (nullptr) используем diskC как диск по
    // умолчанию.
    uint8_t sel = diskSelect->get();
    Disk* activeDisk = (sel == 1) ? diskC
        : (sel == 2) ? diskD
        : ((Disk::lastExecDisk != nullptr) ? Disk::lastExecDisk : diskC);
    std::ifstream file(activeDisk->getCurrentPath() / nameAsString(), std::ios::binary);

    if (!file)
    {
        status = 1;
        return;
    }

    std::vector<uint8_t> data(
        (std::istreambuf_iterator<char>(file)),
        std::istreambuf_iterator<char>()
    );

    // Минимальный размер - до конца order-таблицы и сигнатуры
    // (заголовок + 31 дескриптор сэмпла + order-таблица + сигнатура).
    if (data.size() < 1084)
    {
        status = 3;
        return;
    }

    // Сигнатура - поддерживаем только стандартный 4-канальный/
    // 31-сэмпловый ProTracker MOD (см. ASSEMBLY.md, "ModLoader" про
    // формат и почему остальные варианты не поддержаны).
    std::string signature(reinterpret_cast<const char*>(&data[1080]), 4);
    if (signature != "M.K." && signature != "M!K!" && signature != "FLT4" && signature != "4CHN")
    {
        status = 2;
        return;
    }

    ModSong song;
    song.samples.resize(32);   // индекс 0 не используется - см. ModSong

    size_t sampleDataLengths[32] = {};

    for (int i = 1; i <= 31; i++)
    {
        size_t offset = 20 + static_cast<size_t>(i - 1) * 30;

        uint16_t lengthWords = readBE16(data, offset + 22);
        uint8_t volume = data[offset + 25];
        uint16_t repeatOffsetWords = readBE16(data, offset + 26);
        uint16_t repeatLengthWords = readBE16(data, offset + 28);

        sampleDataLengths[i] = static_cast<size_t>(lengthWords) * 2;

        ModSample& sample = song.samples[i];
        sample.volume = std::min<uint8_t>(64, volume);
        sample.repeatOffset = static_cast<uint32_t>(repeatOffsetWords) * 2;
        sample.repeatLength = static_cast<uint32_t>(repeatLengthWords) * 2;
    }

    uint8_t songLength = data[950];
    if (songLength < 1) songLength = 1;
    if (songLength > 128) songLength = 128;

    uint8_t restartPosition = data[951];
    if (restartPosition >= songLength)
    {
        restartPosition = 0;
    }

    song.songLength = songLength;
    song.restartPosition = restartPosition;

    song.orderTable.assign(data.begin() + 952, data.begin() + 952 + 128);

    // Число паттернов - максимум по ВСЕЙ order-таблице (128 записей,
    // не только используемые songLength штук) - так принято у
    // большинства MOD-файлов/плееров, "лишние" записи иногда всё
    // равно указывают на существующие паттерны.
    int numPatterns = 0;
    for (int i = 0; i < 128; i++)
    {
        numPatterns = std::max(numPatterns, static_cast<int>(song.orderTable[i]) + 1);
    }

    size_t patternsOffset = 1084;
    size_t patternsSize = static_cast<size_t>(numPatterns) * 1024;

    if (data.size() < patternsOffset + patternsSize)
    {
        status = 3;
        return;
    }

    song.patterns.resize(numPatterns);

    for (int p = 0; p < numPatterns; p++)
    {
        size_t patternBase = patternsOffset + static_cast<size_t>(p) * 1024;

        for (int r = 0; r < 64; r++)
        {
            for (int c = 0; c < 4; c++)
            {
                size_t cellOffset = patternBase + (static_cast<size_t>(r) * 4 + c) * 4;

                uint8_t b0 = data[cellOffset];
                uint8_t b1 = data[cellOffset + 1];
                uint8_t b2 = data[cellOffset + 2];
                uint8_t b3 = data[cellOffset + 3];

                ModCell& cell = song.patterns[p].cells[r][c];
                cell.sampleNumber = (b0 & 0xF0) | (b2 >> 4);
                cell.period = (static_cast<uint16_t>(b0 & 0x0F) << 8) | b1;
                cell.effect = b2 & 0x0F;
                cell.param = b3;
            }
        }
    }

    // PCM-данные сэмплов - встык, сразу после всех паттернов, в
    // порядке дескрипторов 1..31.
    size_t sampleDataOffset = patternsOffset + patternsSize;

    for (int i = 1; i <= 31; i++)
    {
        size_t len = sampleDataLengths[i];
        if (len == 0)
        {
            continue;
        }

        if (sampleDataOffset + len > data.size())
        {
            // Файл обрезан - берём сколько есть, не падаем.
            len = (sampleDataOffset < data.size()) ? (data.size() - sampleDataOffset) : 0;
        }

        song.samples[i].data.resize(len);
        for (size_t j = 0; j < len; j++)
        {
            song.samples[i].data[j] = static_cast<int8_t>(data[sampleDataOffset + j]);
        }

        sampleDataOffset += sampleDataLengths[i];
    }

    soundCard->loadSong(std::move(song));
    status = 0;
}
