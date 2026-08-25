#include "MatrixLoader.h"
#include "Disk.h"

#include <fstream>
#include <sstream>

MatrixLoader::MatrixLoader(Disk* diskC)
    : diskC(diskC)
{
    for (int i = 0; i < 12; i++)
    {
        name[i] = 0;
    }

    status = 0;
    width = 0;
    height = 0;

    cellXLow = cellXHigh = cellYLow = cellYHigh = 0;
}

std::string MatrixLoader::nameAsString() const
{
    std::string result;

    for (int i = 0; i < 12 && name[i] != 0; i++)
    {
        result += static_cast<char>(name[i]);
    }

    return result;
}

int MatrixLoader::combine(uint8_t low, uint8_t high)
{
    return static_cast<int>(static_cast<uint16_t>(low) | (static_cast<uint16_t>(high) << 8));
}

uint8_t MatrixLoader::read(uint32_t address)
{
    if (address <= REG_NAME_LAST)
    {
        return name[address];
    }

    switch (address)
    {
    case REG_STATUS: return status;
    case REG_WIDTH_LOW: return static_cast<uint8_t>(width & 0xFF);
    case REG_WIDTH_HIGH: return static_cast<uint8_t>((width >> 8) & 0xFF);
    case REG_HEIGHT_LOW: return static_cast<uint8_t>(height & 0xFF);
    case REG_HEIGHT_HIGH: return static_cast<uint8_t>((height >> 8) & 0xFF);
    case REG_CELL_X_LOW: return cellXLow;
    case REG_CELL_X_HIGH: return cellXHigh;
    case REG_CELL_Y_LOW: return cellYLow;
    case REG_CELL_Y_HIGH: return cellYHigh;
    case REG_CELL_VALUE: return queryCell();
    default: return 0;
    }
}

void MatrixLoader::write(uint32_t address, uint8_t value)
{
    if (address <= REG_NAME_LAST)
    {
        name[address] = value;
        return;
    }

    switch (address)
    {
    case REG_COMMAND:
        if (value == 1)
        {
            load();
        }
        return;

    case REG_CELL_X_LOW: cellXLow = value; return;
    case REG_CELL_X_HIGH: cellXHigh = value; return;
    case REG_CELL_Y_LOW: cellYLow = value; return;
    case REG_CELL_Y_HIGH: cellYHigh = value; return;

    default:
        return;
    }
}

uint8_t MatrixLoader::queryCell() const
{
    int x = combine(cellXLow, cellXHigh);
    int y = combine(cellYLow, cellYHigh);

    if (x < 0 || y < 0 || x >= width || y >= height)
    {
        return 0;
    }

    return matrix[static_cast<size_t>(y) * width + x];
}

void MatrixLoader::load()
{
    // lastExecDisk - см. MapLoader::load() про тот же приём: какой диск
    // реально запустил (через exec) текущую программу.
    Disk* activeDisk = (Disk::lastExecDisk != nullptr) ? Disk::lastExecDisk : diskC;
    std::ifstream file(activeDisk->getCurrentPath() / nameAsString());

    if (!file)
    {
        status = 1;
        return;
    }

    // Формат - как у MapLoader (см. MapLoader.cpp), но полный диапазон
    // байта (0-255, не 0-127) - значение ячейки тут произвольное число, а
    // не индекс тайла.
    std::vector<std::vector<uint8_t>> rows;
    std::string line;

    while (std::getline(file, line))
    {
        std::istringstream lineStream(line);
        std::vector<uint8_t> row;
        int value;

        while (lineStream >> value)
        {
            if (value < 0 || value > 255)
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

    size_t rowWidth = rows[0].size();

    for (const auto& row : rows)
    {
        if (row.size() != rowWidth)
        {
            status = 2; // не прямоугольная матрица
            return;
        }
    }

    matrix.clear();
    matrix.reserve(rowWidth * rows.size());

    for (const auto& row : rows)
    {
        matrix.insert(matrix.end(), row.begin(), row.end());
    }

    width = static_cast<int>(rowWidth);
    height = static_cast<int>(rows.size());
    status = 0;
}
