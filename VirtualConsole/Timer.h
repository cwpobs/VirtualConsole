#pragma once

#include "Device.h"

class Timer : public Device
{
public:

    Timer();

    uint8_t read(uint16_t address) override;
    void write(uint16_t address, uint8_t value) override;

    void tick() override;

private:

    uint16_t counter;
};
