#pragma once

#include "Device.h"

#include <cstdint>
#include <string>
#include <vector>

class Disk;

// Обобщённый загрузчик "любой карты, описываемой матрицей чисел" (карта
// уровня, коллизии, что угодно) - в отличие от MapLoader (см. MapLoader.h),
// который толкает результат ОДНИМ вызовом в VideoCard::setTileMap и
// ограничен диапазоном тайла 0-127, этот загрузчик:
//  - хранит матрицу У СЕБЯ (ничего никуда не пушит - не завязан на
//    VideoCard/рендеринг),
//  - допускает полный диапазон байта (0-255) - значение ячейки не индекс
//    тайла, а произвольное число (высота стопки, тип материала и т.п.),
//  - даёт ОБРАТНОЕ чтение отдельных ячеек по (x,y) - то, чего у MapLoader
//    нет вообще (см. misty-zooming-bee.md про "no query API").
// MapLoader НЕ трогаем/не переиспользуем - от него зависят TILEDEMO.ASM/
// TSCROLL.MC/SNOW3D.MC, ломать их незачем.
//
// Формат файла - тот же текстовый (строки чисел через пробел, прямоугольная
// матрица), парсинг на C++ по тем же причинам, что и у MapLoader/PngLoader -
// разбор текста в ассемблере этого CPU был бы неоправданно громоздким.
class MatrixLoader : public Device
{
public:

    explicit MatrixLoader(Disk* diskC);

    uint8_t read(uint32_t address) override;
    void write(uint32_t address, uint8_t value) override;

private:

    static const uint32_t REG_NAME_FIRST = 0;
    static const uint32_t REG_NAME_LAST = 11;
    static const uint32_t REG_COMMAND = 12;
    static const uint32_t REG_STATUS = 13;
    static const uint32_t REG_WIDTH_LOW = 14;
    static const uint32_t REG_WIDTH_HIGH = 15;
    static const uint32_t REG_HEIGHT_LOW = 16;
    static const uint32_t REG_HEIGHT_HIGH = 17;
    static const uint32_t REG_CELL_X_LOW = 18;
    static const uint32_t REG_CELL_X_HIGH = 19;
    static const uint32_t REG_CELL_Y_LOW = 20;
    static const uint32_t REG_CELL_Y_HIGH = 21;
    static const uint32_t REG_CELL_VALUE = 22;

    Disk* diskC;

    uint8_t name[12];
    uint8_t status;

    int width;
    int height;
    std::vector<uint8_t> matrix;

    uint8_t cellXLow, cellXHigh, cellYLow, cellYHigh;

    std::string nameAsString() const;
    static int combine(uint8_t low, uint8_t high);

    void load();
    uint8_t queryCell() const;
};
