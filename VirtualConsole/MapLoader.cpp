#include "MapLoader.h"
#include "VideoCard.h"
#include "Disk.h"

#include <fstream>
#include <sstream>
#include <vector>

MapLoader::MapLoader(VideoCard* videoCard, Disk* diskC)
    : videoCard(videoCard), diskC(diskC)
{
    for (int i = 0; i < 12; i++)
    {
        name[i] = 0;
    }

    status = 0;
}

std::string MapLoader::nameAsString() const
{
    std::string result;

    for (int i = 0; i < 12 && name[i] != 0; i++)
    {
        result += static_cast<char>(name[i]);
    }

    return result;
}

uint8_t MapLoader::read(uint32_t address)
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

void MapLoader::write(uint32_t address, uint8_t value)
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

void MapLoader::load()
{
    std::ifstream file(diskC->getCurrentPath() / nameAsString());

    if (!file)
    {
        status = 1;
        return;
    }

    // Формат (см. ASSEMBLY.md, "MapLoader"): каждая строка файла -
    // одна строка карты, десятичные индексы тайлов (0-127) через
    // пробел, все строки одинаковой длины (прямоугольная карта).
    // Разбор целиком на стороне C++ - парсить текст в ассемблере
    // этого CPU было бы так же неоправданно, как декодировать PNG.
    std::vector<std::vector<uint8_t>> rows;
    std::string line;

    while (std::getline(file, line))
    {
        std::istringstream lineStream(line);
        std::vector<uint8_t> row;
        int value;

        while (lineStream >> value)
        {
            if (value < 0 || value > 127)
            {
                status = 2;
                return;
            }

            row.push_back(static_cast<uint8_t>(value));
        }

        if (!row.empty())
        {
            rows.push_back(row);
        }
    }

    if (rows.empty())
    {
        status = 2;
        return;
    }

    size_t width = rows[0].size();

    for (const auto& row : rows)
    {
        if (row.size() != width)
        {
            status = 2;   // не прямоугольная карта - строки разной длины
            return;
        }
    }

    std::vector<uint8_t> flat;
    flat.reserve(width * rows.size());

    for (const auto& row : rows)
    {
        flat.insert(flat.end(), row.begin(), row.end());
    }

    videoCard->setTileMap(static_cast<int>(width), static_cast<int>(rows.size()), flat.data());
    status = 0;
}
