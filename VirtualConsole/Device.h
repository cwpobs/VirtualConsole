#pragma once

#include <cstdint>

class Device
{
public:

    virtual ~Device() = default;

    virtual uint8_t read(uint32_t address) = 0;
    virtual void write(uint32_t address, uint8_t value) = 0;

    virtual void tick() {}

    virtual bool interruptPending() { return false; }
};
