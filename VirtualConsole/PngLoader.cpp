#include "PngLoader.h"
#include "VideoCard.h"
#include "Disk.h"

#define STB_IMAGE_IMPLEMENTATION
#define STBI_ONLY_PNG
#include "stb_image.h"

PngLoader::PngLoader(VideoCard* videoCard, Disk* diskC)
    : videoCard(videoCard), diskC(diskC)
{
    for (int i = 0; i < 12; i++)
    {
        name[i] = 0;
    }

    srcXLow = srcXHigh = srcYLow = srcYHigh = 0;
    spriteIndex = 0;
    tileIndex = 0;
    status = 0;

    imageWidth = 0;
    imageHeight = 0;
}

std::string PngLoader::nameAsString() const
{
    std::string result;

    for (int i = 0; i < 12 && name[i] != 0; i++)
    {
        result += static_cast<char>(name[i]);
    }

    return result;
}

uint16_t PngLoader::srcX() const { return static_cast<uint16_t>(srcXLow) | (static_cast<uint16_t>(srcXHigh) << 8); }
uint16_t PngLoader::srcY() const { return static_cast<uint16_t>(srcYLow) | (static_cast<uint16_t>(srcYHigh) << 8); }

uint8_t PngLoader::read(uint32_t address)
{
    if (address <= REG_NAME_LAST)
    {
        return name[address];
    }

    switch (address)
    {
    case REG_SRC_X_LOW: return srcXLow;
    case REG_SRC_X_HIGH: return srcXHigh;
    case REG_SRC_Y_LOW: return srcYLow;
    case REG_SRC_Y_HIGH: return srcYHigh;
    case REG_SPRITE_INDEX: return spriteIndex;
    case REG_STATUS: return status;
    case REG_TILE_INDEX: return tileIndex;
    default: return 0;
    }
}

void PngLoader::write(uint32_t address, uint8_t value)
{
    if (address <= REG_NAME_LAST)
    {
        name[address] = value;
        return;
    }

    switch (address)
    {
    case REG_SRC_X_LOW: srcXLow = value; return;
    case REG_SRC_X_HIGH: srcXHigh = value; return;
    case REG_SRC_Y_LOW: srcYLow = value; return;
    case REG_SRC_Y_HIGH: srcYHigh = value; return;
    case REG_SPRITE_INDEX: spriteIndex = value; return;
    case REG_TILE_INDEX: tileIndex = value; return;

    case REG_COMMAND:
        switch (value)
        {
        case 1: load(); break;
        case 2: extract(); break;
        case 3: extractTile(); break;
        default: break;
        }
        return;

    default:
        return;
    }
}

void PngLoader::load()
{
    std::string path = (diskC->getCurrentPath() / nameAsString()).string();

    int width = 0;
    int height = 0;
    int channels = 0;

    // stbi_load декодирует PNG (zlib/deflate) целиком в C++ - именно
    // та часть, которую реализовать в ассемблере этого CPU нереально
    // (см. ASSEMBLY.md, "PngLoader"). Всегда просим 4 канала (RGBA),
    // даже если в файле их меньше - extract() ниже полагается на
    // фиксированный шаг в 4 байта/пиксель.
    unsigned char* data = stbi_load(path.c_str(), &width, &height, &channels, 4);

    if (data == nullptr)
    {
        status = 1;
        pixels.clear();
        imageWidth = 0;
        imageHeight = 0;
        return;
    }

    pixels.assign(data, data + (static_cast<size_t>(width) * height * 4));
    stbi_image_free(data);

    imageWidth = width;
    imageHeight = height;
    status = 0;
}

void PngLoader::extractInto(int targetIndex, int indexLimit, bool isTile)
{
    if (targetIndex < 0 || targetIndex >= indexLimit)
    {
        status = 3;
        return;
    }

    if (pixels.empty())
    {
        status = 1;
        return;
    }

    uint16_t x = srcX();
    uint16_t y = srcY();

    if (x + CELL_SIZE > imageWidth || y + CELL_SIZE > imageHeight)
    {
        status = 2;
        return;
    }

    uint8_t rgb[CELL_SIZE * CELL_SIZE * 3];

    for (int sy = 0; sy < CELL_SIZE; sy++)
    {
        for (int sx = 0; sx < CELL_SIZE; sx++)
        {
            size_t srcIndex = (static_cast<size_t>(y + sy) * imageWidth + (x + sx)) * 4;
            uint8_t r = pixels[srcIndex];
            uint8_t g = pixels[srcIndex + 1];
            uint8_t b = pixels[srcIndex + 2];
            uint8_t a = pixels[srcIndex + 3];

            int dstIndex = (sy * CELL_SIZE + sx) * 3;

            if (a < 128)
            {
                // Прозрачный пиксель PNG -> цвет-ключ VideoCard (см.
                // ASSEMBLY.md, "Аппаратные спрайты") - ни спрайты, ни
                // тайлы не хранят альфу, только chroma-key.
                rgb[dstIndex] = 255;
                rgb[dstIndex + 1] = 0;
                rgb[dstIndex + 2] = 255;
            }
            else
            {
                rgb[dstIndex] = r;
                rgb[dstIndex + 1] = g;
                rgb[dstIndex + 2] = b;
            }
        }
    }

    if (isTile)
    {
        videoCard->setTileBitmap(targetIndex, rgb);
    }
    else
    {
        videoCard->setSpriteBitmap(targetIndex, rgb);
    }

    status = 0;
}

void PngLoader::extract()
{
    extractInto(spriteIndex, 16, false);
}

void PngLoader::extractTile()
{
    extractInto(tileIndex, 128, true);
}
