#pragma once

#include "Device.h"

#include <atomic>

// Один переключаемый бит - виден ли текстовый слой консоли (см.
// VideoConsole.h) поверх графики VideoCard. Ровно один регистр:
// запись 0 - скрыть, любое другое значение - показать; чтение -
// текущее состояние (0/1). По умолчанию (после старта ВМ) - видимый.
//
// Два независимых источника записи:
//  - VideoCard (см. VideoCard::modeOn/modeOff) - автоматически прячет
//    консоль перед стартом графического режима и возвращает после
//    его завершения (см. setVisible/isVisible, не MMIO-путь - вызов
//    напрямую из C++, тем же потоком CPU, что пишет MODE_ON/MODE_OFF).
//  - Сама программа через MMIO (poke(CONSOLE_VISIBLE, ...) в мини-C,
//    см. Compiler.cpp, kDevicePrelude) - "крутой комбинированный
//    режим": включить консоль обратно, пока графика уже активна, и
//    печатать текст (print_char/set_color и т.п. - они и так пишут в
//    TextVRAM/TextAttr в любой момент, этот регистр только решает,
//    рисовать ли то, что там накопилось).
//
// std::atomic - читается из рендер-потока VideoConsole (см. его
// renderThreadMain) и пишется из потока CPU (MMIO write() и
// VideoCard::modeOn/modeOff) - двух источников записи без атомарности
// было бы достаточно для гонки на одном байте.
class ConsoleLayer : public Device
{
public:

    ConsoleLayer();

    uint8_t read(uint32_t address) override;
    void write(uint32_t address, uint8_t value) override;

    // Non-MMIO C++ доступ - для VideoCard (авто-переключение на
    // MODE_ON/MODE_OFF) и VideoConsole (рендер-поток решает, рисовать
    // ли текст поверх графики).
    void setVisible(bool value);
    bool isVisible() const;

private:

    std::atomic<bool> visible;
};
