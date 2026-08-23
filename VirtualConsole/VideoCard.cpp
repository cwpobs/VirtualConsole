#include "VideoCard.h"

#include <cstring>

VideoCard::VideoCard()
    : active(false)
{
    xLow = xHigh = yLow = yHigh = 0;
    wLow = wHigh = hLow = hHigh = 0;
    r = g = b = 0;
    status = 0;

    for (int i = 0; i < FB_SIZE; i++)
    {
        framebuffer[i] = 0;
    }

    spriteIndex = 0;
    spritePixelLow = spritePixelHigh = 0;
    spriteR = spriteG = spriteB = 0;
    spriteStatus = 0;

    for (int s = 0; s < SPRITE_COUNT; s++)
    {
        // Пустой спрайт по умолчанию - целиком цвет-ключ прозрачности,
        // невидим по контенту даже до первого явного CLEAR/WRITE_PIXEL.
        for (int i = 0; i < SPRITE_PIXELS * CHANNELS; i += CHANNELS)
        {
            spriteData[s][i] = CHROMA_R;
            spriteData[s][i + 1] = CHROMA_G;
            spriteData[s][i + 2] = CHROMA_B;
        }

        spriteX[s] = 0;
        spriteY[s] = 0;
        spriteVisible[s] = false;
    }

    for (int t = 0; t < TILE_SET_COUNT; t++)
    {
        for (int i = 0; i < TILE_PIXELS * CHANNELS; i++)
        {
            tileSetData[t][i] = 0;
        }
    }

    mapWidth = 0;
    mapHeight = 0;   // 0 = карта не загружена, compositeTiles ничего не рисует
    scrollX = 0;
    scrollY = 0;

    for (int i = 0; i < FB_SIZE; i++)
    {
        threeDLayer[i] = 0;
    }
    threeDTouched.assign(WIDTH * HEIGHT, 0);
    threeDActive = false;
}

uint16_t VideoCard::regX() const { return static_cast<uint16_t>(xLow) | (static_cast<uint16_t>(xHigh) << 8); }
uint16_t VideoCard::regY() const { return static_cast<uint16_t>(yLow) | (static_cast<uint16_t>(yHigh) << 8); }
uint16_t VideoCard::regW() const { return static_cast<uint16_t>(wLow) | (static_cast<uint16_t>(wHigh) << 8); }
uint16_t VideoCard::regH() const { return static_cast<uint16_t>(hLow) | (static_cast<uint16_t>(hHigh) << 8); }
uint16_t VideoCard::regSpritePixel() const { return static_cast<uint16_t>(spritePixelLow) | (static_cast<uint16_t>(spritePixelHigh) << 8); }

uint8_t VideoCard::read(uint32_t address)
{
    switch (address)
    {
    case REG_X_LOW: return xLow;
    case REG_X_HIGH: return xHigh;
    case REG_Y_LOW: return yLow;
    case REG_Y_HIGH: return yHigh;
    case REG_W_LOW: return wLow;
    case REG_W_HIGH: return wHigh;
    case REG_H_LOW: return hLow;
    case REG_H_HIGH: return hHigh;
    case REG_R: return r;
    case REG_G: return g;
    case REG_B: return b;
    case REG_STATUS: return status;

    case REG_SPRITE_INDEX: return spriteIndex;
    case REG_SPRITE_PIXEL_LOW: return spritePixelLow;
    case REG_SPRITE_PIXEL_HIGH: return spritePixelHigh;
    case REG_SPRITE_X_LOW: return spriteX[spriteIndex] & 0xFF;
    case REG_SPRITE_X_HIGH: return (spriteX[spriteIndex] >> 8) & 0xFF;
    case REG_SPRITE_Y_LOW: return spriteY[spriteIndex] & 0xFF;
    case REG_SPRITE_Y_HIGH: return (spriteY[spriteIndex] >> 8) & 0xFF;
    case REG_SPRITE_VISIBLE: return spriteVisible[spriteIndex] ? 1 : 0;
    case REG_SPRITE_R: return spriteR;
    case REG_SPRITE_G: return spriteG;
    case REG_SPRITE_B: return spriteB;
    case REG_SPRITE_STATUS: return spriteStatus;

    case REG_SCROLL_X_LOW: return scrollX & 0xFF;
    case REG_SCROLL_X_HIGH: return (scrollX >> 8) & 0xFF;
    case REG_SCROLL_Y_LOW: return scrollY & 0xFF;
    case REG_SCROLL_Y_HIGH: return (scrollY >> 8) & 0xFF;

    default: return 0;
    }
}

void VideoCard::write(uint32_t address, uint8_t value)
{
    switch (address)
    {
    case REG_X_LOW: xLow = value; return;
    case REG_X_HIGH: xHigh = value; return;
    case REG_Y_LOW: yLow = value; return;
    case REG_Y_HIGH: yHigh = value; return;
    case REG_W_LOW: wLow = value; return;
    case REG_W_HIGH: wHigh = value; return;
    case REG_H_LOW: hLow = value; return;
    case REG_H_HIGH: hHigh = value; return;
    case REG_R: r = value; return;
    case REG_G: g = value; return;
    case REG_B: b = value; return;

    case REG_COMMAND:
        switch (value)
        {
        case 1: modeOn(); break;
        case 2: modeOff(); break;
        case 3: clear(); break;
        case 4: setPixel(); break;
        case 5: fillRect(); break;
        default: break;
        }
        return;

    case REG_SPRITE_INDEX:
        // spriteIndex индексирует массивы spriteX/Y/Visible/Data
        // напрямую - невалидное значение здесь означало бы выход за
        // границы массива при следующем же обращении, поэтому
        // отклоняем его тут же, а не там, где уже поздно.
        if (value >= SPRITE_COUNT)
        {
            spriteStatus = 1;
            return;
        }
        spriteIndex = value;
        spriteStatus = 0;
        return;

    case REG_SPRITE_PIXEL_LOW: spritePixelLow = value; return;
    case REG_SPRITE_PIXEL_HIGH: spritePixelHigh = value; return;

    case REG_SPRITE_X_LOW:
    {
        std::lock_guard<std::mutex> lock(framebufferMutex);
        spriteX[spriteIndex] = (spriteX[spriteIndex] & 0xFF00) | value;
        return;
    }
    case REG_SPRITE_X_HIGH:
    {
        std::lock_guard<std::mutex> lock(framebufferMutex);
        spriteX[spriteIndex] = (spriteX[spriteIndex] & 0x00FF) | (static_cast<uint16_t>(value) << 8);
        return;
    }
    case REG_SPRITE_Y_LOW:
    {
        std::lock_guard<std::mutex> lock(framebufferMutex);
        spriteY[spriteIndex] = (spriteY[spriteIndex] & 0xFF00) | value;
        return;
    }
    case REG_SPRITE_Y_HIGH:
    {
        std::lock_guard<std::mutex> lock(framebufferMutex);
        spriteY[spriteIndex] = (spriteY[spriteIndex] & 0x00FF) | (static_cast<uint16_t>(value) << 8);
        return;
    }
    case REG_SPRITE_VISIBLE:
    {
        std::lock_guard<std::mutex> lock(framebufferMutex);
        spriteVisible[spriteIndex] = (value != 0);
        return;
    }

    case REG_SPRITE_R: spriteR = value; return;
    case REG_SPRITE_G: spriteG = value; return;
    case REG_SPRITE_B: spriteB = value; return;

    case REG_SPRITE_COMMAND:
        switch (value)
        {
        case 1: spriteWritePixel(); break;
        case 2: spriteClear(); break;
        default: break;
        }
        return;

    case REG_SCROLL_X_LOW:
    {
        std::lock_guard<std::mutex> lock(framebufferMutex);
        scrollX = (scrollX & 0xFF00) | value;
        clampScroll();
        return;
    }
    case REG_SCROLL_X_HIGH:
    {
        std::lock_guard<std::mutex> lock(framebufferMutex);
        scrollX = (scrollX & 0x00FF) | (static_cast<uint16_t>(value) << 8);
        clampScroll();
        return;
    }
    case REG_SCROLL_Y_LOW:
    {
        std::lock_guard<std::mutex> lock(framebufferMutex);
        scrollY = (scrollY & 0xFF00) | value;
        clampScroll();
        return;
    }
    case REG_SCROLL_Y_HIGH:
    {
        std::lock_guard<std::mutex> lock(framebufferMutex);
        scrollY = (scrollY & 0x00FF) | (static_cast<uint16_t>(value) << 8);
        clampScroll();
        return;
    }

    default:
        return;
    }
}

void VideoCard::clear()
{
    std::lock_guard<std::mutex> lock(framebufferMutex);

    for (int i = 0; i < FB_SIZE; i += CHANNELS)
    {
        framebuffer[i] = r;
        framebuffer[i + 1] = g;
        framebuffer[i + 2] = b;
    }

    status = 0;
}

void VideoCard::setPixel()
{
    uint16_t x = regX();
    uint16_t y = regY();

    if (x >= WIDTH || y >= HEIGHT)
    {
        status = 1;
        return;
    }

    std::lock_guard<std::mutex> lock(framebufferMutex);

    int index = (y * WIDTH + x) * CHANNELS;
    framebuffer[index] = r;
    framebuffer[index + 1] = g;
    framebuffer[index + 2] = b;

    status = 0;
}

void VideoCard::fillRect()
{
    uint16_t x = regX();
    uint16_t y = regY();
    uint16_t w = regW();
    uint16_t h = regH();

    if (x >= WIDTH || y >= HEIGHT)
    {
        status = 1;
        return;
    }

    uint16_t x2 = x + w;
    uint16_t y2 = y + h;
    if (x2 > WIDTH) x2 = WIDTH;
    if (y2 > HEIGHT) y2 = HEIGHT;

    std::lock_guard<std::mutex> lock(framebufferMutex);

    for (uint16_t py = y; py < y2; py++)
    {
        int rowBase = py * WIDTH * CHANNELS;
        for (uint16_t px = x; px < x2; px++)
        {
            int index = rowBase + px * CHANNELS;
            framebuffer[index] = r;
            framebuffer[index + 1] = g;
            framebuffer[index + 2] = b;
        }
    }

    status = 0;
}

void VideoCard::spriteWritePixel()
{
    uint16_t pixel = regSpritePixel();

    if (pixel >= SPRITE_PIXELS)
    {
        spriteStatus = 1;
        return;
    }

    {
        std::lock_guard<std::mutex> lock(framebufferMutex);

        int index = pixel * CHANNELS;
        spriteData[spriteIndex][index] = spriteR;
        spriteData[spriteIndex][index + 1] = spriteG;
        spriteData[spriteIndex][index + 2] = spriteB;
    }

    // Автоинкремент по модулю SPRITE_PIXELS - удобно заливать весь
    // битмап подряд простым циклом без пересчёта индекса вручную
    // (см. ASSEMBLY.md, "VideoCard").
    uint16_t next = static_cast<uint16_t>((pixel + 1) % SPRITE_PIXELS);
    spritePixelLow = next & 0xFF;
    spritePixelHigh = (next >> 8) & 0xFF;

    spriteStatus = 0;
}

void VideoCard::spriteClear()
{
    std::lock_guard<std::mutex> lock(framebufferMutex);

    for (int i = 0; i < SPRITE_PIXELS * CHANNELS; i += CHANNELS)
    {
        spriteData[spriteIndex][i] = CHROMA_R;
        spriteData[spriteIndex][i + 1] = CHROMA_G;
        spriteData[spriteIndex][i + 2] = CHROMA_B;
    }

    spriteStatus = 0;
}

void VideoCard::clampScroll()
{
    // Вызывается уже под framebufferMutex (см. write() выше) -
    // отдельной блокировки тут нет и не должно быть.
    if (mapWidth <= 0 || mapHeight <= 0)
    {
        scrollX = 0;
        scrollY = 0;
        return;
    }

    int maxScrollX = mapWidth * TILE_SIZE - WIDTH;
    int maxScrollY = mapHeight * TILE_SIZE - HEIGHT;

    if (maxScrollX < 0) maxScrollX = 0;
    if (maxScrollY < 0) maxScrollY = 0;

    if (scrollX > maxScrollX) scrollX = static_cast<uint16_t>(maxScrollX);
    if (scrollY > maxScrollY) scrollY = static_cast<uint16_t>(maxScrollY);
}

void VideoCard::setTileBitmap(int index, const uint8_t* rgb)
{
    if (index < 0 || index >= TILE_SET_COUNT)
    {
        return;
    }

    std::lock_guard<std::mutex> lock(framebufferMutex);
    memcpy(tileSetData[index], rgb, TILE_PIXELS * CHANNELS);
}

void VideoCard::setTileMap(int width, int height, const uint8_t* indices)
{
    std::lock_guard<std::mutex> lock(framebufferMutex);

    if (width <= 0 || height <= 0)
    {
        tileMap.clear();
        mapWidth = 0;
        mapHeight = 0;
        clampScroll();
        return;
    }

    tileMap.assign(indices, indices + (static_cast<size_t>(width) * height));
    mapWidth = width;
    mapHeight = height;

    // Новая карта могла оказаться меньше предыдущей - сбрасываем
    // скролл в начало, а не оставляем его висеть за новым краем карты.
    scrollX = 0;
    scrollY = 0;
}

void VideoCard::compositeTiles(uint8_t* staging) const
{
    // Вызывающий (compositeFrame) уже держит framebufferMutex - см.
    // compositeSprites про тот же приём.
    if (mapHeight <= 0 || mapWidth <= 0)
    {
        return;
    }

    for (int py = 0; py < HEIGHT; py++)
    {
        int worldY = scrollY + py;
        int tileRow = worldY / TILE_SIZE;
        int localY = worldY % TILE_SIZE;

        for (int px = 0; px < WIDTH; px++)
        {
            int dstIndex = (py * WIDTH + px) * CHANNELS;

            int worldX = scrollX + px;
            int tileCol = worldX / TILE_SIZE;

            if (tileRow < 0 || tileRow >= mapHeight || tileCol < 0 || tileCol >= mapWidth)
            {
                staging[dstIndex] = 0;
                staging[dstIndex + 1] = 0;
                staging[dstIndex + 2] = 0;
                continue;
            }

            int localX = worldX % TILE_SIZE;
            uint8_t tileIndex = tileMap[tileRow * mapWidth + tileCol];

            int srcIndex = (localY * TILE_SIZE + localX) * CHANNELS;
            staging[dstIndex] = tileSetData[tileIndex][srcIndex];
            staging[dstIndex + 1] = tileSetData[tileIndex][srcIndex + 1];
            staging[dstIndex + 2] = tileSetData[tileIndex][srcIndex + 2];
        }
    }
}

void VideoCard::setThreeDLayer(const uint8_t* rgb, const uint8_t* touchedMask)
{
    std::lock_guard<std::mutex> lock(framebufferMutex);

    memcpy(threeDLayer, rgb, FB_SIZE);
    threeDTouched.assign(touchedMask, touchedMask + (WIDTH * HEIGHT));
    threeDActive = true;
}

void VideoCard::compositeThreeD(uint8_t* staging) const
{
    // Вызывающий (compositeFrame) уже держит framebufferMutex - см.
    // compositeSprites про тот же приём. Пока Gpu3D ни разу не сделал
    // PRESENT, threeDActive==false - слой полностью пропускается,
    // старые демо без 3D не видят разницы.
    if (!threeDActive)
    {
        return;
    }

    for (int i = 0; i < WIDTH * HEIGHT; i++)
    {
        if (!threeDTouched[i])
        {
            continue;   // пиксель, которого 3D-кадр не коснулся - оставляем то, что под ним
        }

        int idx = i * CHANNELS;
        staging[idx] = threeDLayer[idx];
        staging[idx + 1] = threeDLayer[idx + 1];
        staging[idx + 2] = threeDLayer[idx + 2];
    }
}

void VideoCard::setSpriteBitmap(int index, const uint8_t* rgb)
{
    if (index < 0 || index >= SPRITE_COUNT)
    {
        return;
    }

    std::lock_guard<std::mutex> lock(framebufferMutex);
    memcpy(spriteData[index], rgb, SPRITE_PIXELS * CHANNELS);
}

void VideoCard::compositeSprites(uint8_t* staging) const
{
    // Вызывающий (compositeFrame) уже держит framebufferMutex на
    // время снимка фона - композиция спрайтов идёт в ТОМ ЖЕ снимке,
    // отдельной блокировки тут не нужно (mutex не рекурсивный).
    for (int s = 0; s < SPRITE_COUNT; s++)
    {
        if (!spriteVisible[s])
        {
            continue;
        }

        int baseX = spriteX[s];
        int baseY = spriteY[s];

        for (int sy = 0; sy < SPRITE_SIZE; sy++)
        {
            int py = baseY + sy;
            if (py < 0 || py >= HEIGHT)
            {
                continue;
            }

            for (int sx = 0; sx < SPRITE_SIZE; sx++)
            {
                int px = baseX + sx;
                if (px < 0 || px >= WIDTH)
                {
                    continue;
                }

                int srcIndex = (sy * SPRITE_SIZE + sx) * CHANNELS;
                uint8_t sr = spriteData[s][srcIndex];
                uint8_t sg = spriteData[s][srcIndex + 1];
                uint8_t sb = spriteData[s][srcIndex + 2];

                if (sr == CHROMA_R && sg == CHROMA_G && sb == CHROMA_B)
                {
                    continue;   // цвет-ключ - прозрачный пиксель
                }

                int dstIndex = (py * WIDTH + px) * CHANNELS;
                staging[dstIndex] = sr;
                staging[dstIndex + 1] = sg;
                staging[dstIndex + 2] = sb;
            }
        }
    }
}

void VideoCard::modeOn()
{
    active = true;
}

void VideoCard::modeOff()
{
    active = false;
}

bool VideoCard::isActive() const
{
    return active;
}

void VideoCard::compositeFrame(uint8_t* rgb) const
{
    std::lock_guard<std::mutex> lock(framebufferMutex);
    memcpy(rgb, framebuffer, FB_SIZE);
    compositeTiles(rgb);    // тайлы (если карта загружена) поверх фона
    compositeThreeD(rgb);   // 3D-слой (если активен) поверх тайлов
    compositeSprites(rgb);  // спрайты (UI) - всегда поверх всех слоёв
}
