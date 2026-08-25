#pragma once

#include "Device.h"

#include <cstdint>
#include <mutex>

// Мышь: относительное перемещение (дельта с прошлого чтения), не абсолютные
// координаты - демкам, ради которых это устройство появилось, нужен режим
// "мышь крутит камеру" (FPS-style mouse-look), а не курсор поверх экрана
// VideoCard (пришлось бы разворачивать letterbox-масштабирование окна, см.
// VideoConsole::compositeVideoCardLayer - оно того не стоит).
//
// Мини-C сравнивает/складывает свой 8-битный int через wraparound-арифметику
// (см. ASSEMBLY.md, "Мини-C"), а не как настоящее знаковое число - поэтому
// дельта передаётся как ЗНАК+МОДУЛЬ (два байта на ось), а не один знаковый
// байт: со знаком+модулем прибавить/вычесть дельту к yaw/pitch - это просто
// if(sign==0) добавить, иначе вычесть, без двусмысленности wraparound.
//
// Как и Keyboard, обновляется из потока окна VideoConsole (WM_MOUSEMOVE/
// WM_LBUTTONDOWN/...), а читается из потока CPU - отсюда мьютекс.
class Mouse : public Device
{
public:

    Mouse();

    uint8_t read(uint32_t address) override;
    void write(uint32_t address, uint8_t value) override;

    // Вызывается из потока окна (VideoConsole::WindowProc) на WM_MOUSEMOVE -
    // dx/dy это разница в пикселях с прошлой позиции курсора, копится до
    // чтения с CPU (см. queueMutex).
    void injectMouseMove(int dx, int dy);

    // WM_LBUTTONDOWN/UP, WM_RBUTTONDOWN/UP.
    void setButton(int buttonBit, bool down);

    bool isCaptureEnabled();

private:

    static const uint32_t REG_DELTA_X_SIGN = 0;
    static const uint32_t REG_DELTA_X_MAG = 1;
    static const uint32_t REG_DELTA_Y_SIGN = 2;
    static const uint32_t REG_DELTA_Y_MAG = 3;
    static const uint32_t REG_BUTTONS = 4;
    static const uint32_t REG_CONTROL = 5;

    std::mutex stateMutex;

    int accumDx;
    int accumDy;
    uint8_t buttons;
    bool captureEnabled;

    static uint8_t clampMagnitude(int value);
};
