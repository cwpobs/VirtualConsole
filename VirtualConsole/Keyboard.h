#pragma once

#include "Device.h"

class Keyboard : public Device
{
public:

    Keyboard();

    uint8_t read(uint16_t address) override;
    void write(uint16_t address, uint8_t value) override;

    void tick() override;

    bool interruptPending() override;

private:

    static const int QUEUE_SIZE = 16;

    uint8_t queue[QUEUE_SIZE];
    int head;
    int tail;
    int count;

    bool enabled;
    bool pending;

    bool queueEmpty();
    bool queueFull();

    void queuePush(uint8_t value);
    uint8_t queuePop();
};
