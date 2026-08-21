#pragma once

#include "Device.h"

#include <atomic>
#include <cstdint>
#include <mutex>
#include <thread>

// Видеокарта: растровый режим 320x240 RGB, рисуется в отдельном
// родном окне (Win32 + OpenGL/WGL), пока консоль остаётся текстовым
// терминалом. Framebuffer живёт целиком на C++ стороне устройства -
// НЕ memory-mapped побайтово (320*240*3 = 230400 байт через
// CPU-цикл писались бы непрактично медленно) - вместо этого
// компактный командный протокол (регистры + COMMAND-триггер), как у
// Disk. См. ASSEMBLY.md, раздел "VideoCard".
//
// Рендеринг (окно, message pump, OpenGL) целиком живёт в отдельном
// std::thread, независимом от CPU-цикла. Это принципиально: tick()
// устройства вызывается на КАЖДЫЙ доступ к шине (тысячи раз в
// секунду, см. CPU::busRead/busWrite) - любая тяжёлая работа там
// повторила бы баг с Keyboard (см. Keyboard.h), только гораздо хуже.
// VideoCard вообще не переопределяет tick().
class VideoCard : public Device
{
public:

    VideoCard();
    ~VideoCard() override;

    uint8_t read(uint32_t address) override;
    void write(uint32_t address, uint8_t value) override;

private:

    static const int WIDTH = 320;
    static const int HEIGHT = 240;
    static const int CHANNELS = 3;
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

    uint8_t xLow, xHigh, yLow, yHigh;
    uint8_t wLow, wHigh, hLow, hHigh;
    uint8_t r, g, b;
    uint8_t status;

    uint8_t framebuffer[FB_SIZE];
    std::mutex framebufferMutex;

    std::thread renderThread;
    std::atomic<bool> windowOpen;
    std::atomic<bool> stopRequested;

    uint16_t regX() const;
    uint16_t regY() const;
    uint16_t regW() const;
    uint16_t regH() const;

    void modeOn();
    void modeOff();
    void clear();
    void setPixel();
    void fillRect();

    void renderThreadMain();
};
