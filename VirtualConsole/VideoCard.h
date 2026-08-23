#pragma once

#include "Device.h"

#include <atomic>
#include <cstdint>
#include <mutex>
#include <vector>

// Видеокарта: растровый режим 320x240 RGB + спрайты/тайлы/3D-слой.
// Framebuffer живёт целиком на C++ стороне устройства - НЕ
// memory-mapped побайтово (320*240*3 = 230400 байт через CPU-цикл
// писались бы непрактично медленно) - вместо этого компактный
// командный протокол (регистры + COMMAND-триггер), как у Disk. См.
// ASSEMBLY.md, раздел "VideoCard".
//
// У устройства НЕТ своего окна/потока/OpenGL-контекста - единственный
// экран на весь процесс держит VideoConsole (см. VideoConsole.h), а
// VideoCard - просто ещё один слой в его композиции: MODE_ON/MODE_OFF
// теперь лишь выставляют флаг active (см. isActive()), а не
// открывают/закрывают отдельное окно. VideoConsole::renderThreadMain
// на каждом кадре сам зовёт compositeFrame(), если active, и
// вписывает результат (320x240) в свою канву с сохранением пропорций.
// Экрана без видеоконсоли (console=text в VmConfig, см. VmConfig.h) у
// VideoCard нет - осознанное ограничение: легаси-консоль остаётся
// текстовым резервным выводом, графика ей не нужна.
class VideoCard : public Device
{
public:

    // Размер холста - публичный, VideoConsole использует его для
    // расчёта масштаба при вписывании кадра VideoCard в свою канву
    // (см. compositeFrame/isActive и VideoConsole::renderThreadMain).
    static const int WIDTH = 320;
    static const int HEIGHT = 240;
    static const int CHANNELS = 3;

    VideoCard();

    uint8_t read(uint32_t address) override;
    void write(uint32_t address, uint8_t value) override;

    // Заливает битмап спрайта index целиком из внешнего RGB-буфера
    // (32*32*3 байт) - для устройств вроде PngLoader, которым нужно
    // положить готовую декодированную картинку в спрайт одним вызовом
    // C++, без похода через регистры/WRITE_PIXEL по одному пикселю.
    // index вне 0-15 молча игнорируется.
    void setSpriteBitmap(int index, const uint8_t* rgb);

    // Заливает битмап тайла index (32*32*3 байт RGB) - для PngLoader
    // (EXTRACT_TILE), аналог setSpriteBitmap для тайлсета. index вне
    // 0-127 молча игнорируется.
    void setTileBitmap(int index, const uint8_t* rgb);

    // Кладёт карту тайлов width x height (индексы 0-127, по одному
    // байту на ячейку, width*height байт) - для MapLoader. Заменяет
    // предыдущую карту целиком (включая размеры) и сбрасывает
    // scrollX/scrollY, чтобы не остаться со скроллом за пределами
    // новой карты. width/height <= 0 отключает тайловый слой
    // (compositeTiles ничего не рисует, пока карта не загружена).
    void setTileMap(int width, int height, const uint8_t* indices);

    // Кладёт готовый кадр 3D-слоя целиком (320*240*3 RGB +
    // 320*240 маска "затронутых" пикселей, 0/1) - для Gpu3D (команда
    // PRESENT). Пиксели с touchedMask[i]==0 не перекрывают то, что
    // уже нарисовано на слоях под 3D (фон/тайлы) - см. compositeThreeD.
    // Первый вызов включает 3D-слой в композиции кадра.
    void setThreeDLayer(const uint8_t* rgb, const uint8_t* touchedMask);

    // true между MODE_ON и MODE_OFF - VideoConsole проверяет это перед
    // тем, как звать compositeFrame() на каждом кадре (не тратить
    // время на композицию, пока ни одна программа не включала
    // видеокарту).
    bool isActive() const;

    // Композиция готового кадра (фон + тайлы + 3D-слой + спрайты) в
    // rgb (320*240*3 байт, буфер даёт вызывающий) - то же самое, что
    // раньше собирал перед glDrawPixels свой собственный рендер-поток
    // (см. VideoConsole::renderThreadMain). Лочит framebufferMutex
    // сама - можно звать из любого потока.
    void compositeFrame(uint8_t* rgb) const;

private:

    static const int FB_SIZE = WIDTH * HEIGHT * CHANNELS;

    // Регистры (адреса относительно начала маппинга - см. main.cpp)
    static const uint32_t REG_X_LOW = 0;
    static const uint32_t REG_X_HIGH = 1;
    static const uint32_t REG_Y_LOW = 2;
    static const uint32_t REG_Y_HIGH = 3;
    static const uint32_t REG_W_LOW = 4;
    static const uint32_t REG_W_HIGH = 5;
    static const uint32_t REG_H_LOW = 6;
    static const uint32_t REG_H_HIGH = 7;
    static const uint32_t REG_R = 8;
    static const uint32_t REG_G = 9;
    static const uint32_t REG_B = 10;
    static const uint32_t REG_COMMAND = 11;
    static const uint32_t REG_STATUS = 12;

    // Спрайтовые регистры - продолжение того же адресного блока (см.
    // ASSEMBLY.md, "VideoCard"). SPRITE_X/Y/VISIBLE пишутся напрямую
    // (без команды-триггера) - обновлять позицию каждый кадр должно
    // быть дёшево. SPRITE_PIXEL - индекс 0-1023 (32x32), не влезает
    // в один байт, поэтому LOW/HIGH, как X/Y фона.
    static const uint32_t REG_SPRITE_INDEX = 13;
    static const uint32_t REG_SPRITE_PIXEL_LOW = 14;
    static const uint32_t REG_SPRITE_PIXEL_HIGH = 15;
    static const uint32_t REG_SPRITE_X_LOW = 16;
    static const uint32_t REG_SPRITE_X_HIGH = 17;
    static const uint32_t REG_SPRITE_Y_LOW = 18;
    static const uint32_t REG_SPRITE_Y_HIGH = 19;
    static const uint32_t REG_SPRITE_VISIBLE = 20;
    static const uint32_t REG_SPRITE_R = 21;
    static const uint32_t REG_SPRITE_G = 22;
    static const uint32_t REG_SPRITE_B = 23;
    static const uint32_t REG_SPRITE_COMMAND = 24;
    static const uint32_t REG_SPRITE_STATUS = 25;

    // Скролл тайловой карты - продолжение блока (см. ASSEMBLY.md,
    // "VideoCard"). Пишутся напрямую, без команды (как SPRITE_X/Y) -
    // клэмпятся к границам карты сразу при записи.
    static const uint32_t REG_SCROLL_X_LOW = 26;
    static const uint32_t REG_SCROLL_X_HIGH = 27;
    static const uint32_t REG_SCROLL_Y_LOW = 28;
    static const uint32_t REG_SCROLL_Y_HIGH = 29;

    static const int SPRITE_COUNT = 16;
    static const int SPRITE_SIZE = 32;
    static const int SPRITE_PIXELS = SPRITE_SIZE * SPRITE_SIZE;

    static const int TILE_SET_COUNT = 128;
    static const int TILE_SIZE = 32;
    static const int TILE_PIXELS = TILE_SIZE * TILE_SIZE;

    // Цвет-ключ прозрачности - пиксель спрайта такого цвета не
    // рисуется при композиции поверх фона (см. compositeSprites).
    static const uint8_t CHROMA_R = 255;
    static const uint8_t CHROMA_G = 0;
    static const uint8_t CHROMA_B = 255;

    uint8_t xLow, xHigh, yLow, yHigh;
    uint8_t wLow, wHigh, hLow, hHigh;
    uint8_t r, g, b;
    uint8_t status;

    uint8_t framebuffer[FB_SIZE];
    // mutable - compositeFrame() лочит его из const-метода (см. .cpp).
    mutable std::mutex framebufferMutex;

    uint8_t spriteIndex;
    uint8_t spritePixelLow, spritePixelHigh;
    uint8_t spriteR, spriteG, spriteB;
    uint8_t spriteStatus;

    uint8_t spriteData[SPRITE_COUNT][SPRITE_PIXELS * CHANNELS];
    uint16_t spriteX[SPRITE_COUNT];
    uint16_t spriteY[SPRITE_COUNT];
    bool spriteVisible[SPRITE_COUNT];

    uint8_t tileSetData[TILE_SET_COUNT][TILE_PIXELS * CHANNELS];

    // Карта - индексы тайлов, mapWidth*mapHeight байт, пусто/mapHeight
    // == 0 значит "карта не загружена" - compositeTiles тогда ничего
    // не делает (старые демо без карты не видят разницы).
    std::vector<uint8_t> tileMap;
    int mapWidth;
    int mapHeight;

    uint16_t scrollX;
    uint16_t scrollY;

    // 3D-слой (см. Gpu3D) - заполняется целиком одним вызовом
    // setThreeDLayer, не через регистры. threeDActive==false значит
    // "ни разу не было PRESENT" - compositeThreeD тогда ничего не
    // делает, старые демо без 3D не видят разницы (та же идея, что у
    // mapHeight==0 для тайлов).
    uint8_t threeDLayer[FB_SIZE];
    std::vector<uint8_t> threeDTouched;   // WIDTH*HEIGHT, 0/1
    bool threeDActive;

    // true между MODE_ON и MODE_OFF - см. isActive()/modeOn()/modeOff().
    std::atomic<bool> active;

    uint16_t regX() const;
    uint16_t regY() const;
    uint16_t regW() const;
    uint16_t regH() const;
    uint16_t regSpritePixel() const;

    void modeOn();
    void modeOff();
    void clear();
    void setPixel();
    void fillRect();

    void spriteWritePixel();
    void spriteClear();
    void compositeSprites(uint8_t* staging) const;

    void clampScroll();
    void compositeTiles(uint8_t* staging) const;
    void compositeThreeD(uint8_t* staging) const;
};
