#pragma once

#include "Device.h"

#include <chrono>

class Keyboard : public Device
{
public:

    Keyboard();

    uint8_t read(uint32_t address) override;
    void write(uint32_t address, uint8_t value) override;

    void tick() override;

    bool interruptPending() override;

private:

    static const int QUEUE_SIZE = 16;

    uint8_t queue[QUEUE_SIZE];
    int head;
    int tail;
    int count;

    bool enabled;

    // tick() вызывается на КАЖДОЕ обращение к шине (CPU::busRead/
    // busWrite), а не раз в инструкцию - это тысячи раз в секунду.
    // _kbhit()/_getch() - настоящие системные вызовы Windows, не
    // дешёвая проверка переменной; опрашивать реальную клавиатуру
    // так часто не нужно и заметно тормозит (нашли живым
    // тестированием - shell-команды с большими циклами вроде
    // goto_row_start ощутимо подвисали). Троттлим до ~1 мс - с
    // большим запасом для скорости печати человека.
    std::chrono::steady_clock::time_point lastPoll;

    bool queueEmpty();
    bool queueFull();

    void queuePush(uint8_t value);
    uint8_t queuePop();
};
