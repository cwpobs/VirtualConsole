#pragma once

#include "Device.h"

#include <cstdint>
#include <mutex>

// Состояние "зажата ли клавиша ПРЯМО СЕЙЧАС" - отдельное от Keyboard
// (см. Keyboard.h), которая устроена как очередь "для печати" (по
// одному байту на нажатие) и плохо подходит для непрерывного движения
// персонажа: пока стрелка зажата, Windows шлёт WM_KEYDOWN многократно
// (авто-повтор), а очередь Keyboard консьюмится только по одному байту
// за кадр - при быстром повторе очередь копится/отстаёт, и вдобавок
// половина прочитанных байт - двухбайтовый префикс extended-кода (см.
// VideoConsole.cpp, extendedKeyPrefix), не совпадающий ни с одним
// KEY_UP/DOWN/... - отсюда рывки при движении (см. misty-zooming-bee.md).
//
// KeyState - однобайтовая битовая маска, обновляется VideoConsole
// НАПРЯМУЮ по WM_KEYDOWN/WM_KEYUP (не через очередь) - в любой момент
// отражает текущее состояние стрелок, без потерь и без накопления.
// Keyboard при этом не тронут - им по-прежнему пользуются FM/EDIT и
// разовые действия вроде Ctrl+Q, для которых очередь как раз то, что
// нужно.
class KeyState : public Device
{
public:

    static const uint8_t BIT_UP = 0x01;
    static const uint8_t BIT_DOWN = 0x02;
    static const uint8_t BIT_LEFT = 0x04;
    static const uint8_t BIT_RIGHT = 0x08;

    KeyState();

    uint8_t read(uint32_t address) override;
    void write(uint32_t address, uint8_t value) override;

    // Вызывается из потока окна (VideoConsole::WindowProc) на
    // WM_KEYDOWN/WM_KEYUP - выставляет/сбрасывает один бит.
    void setKeyDown(uint8_t bit, bool down);

private:

    std::mutex maskMutex;
    uint8_t mask;
};
