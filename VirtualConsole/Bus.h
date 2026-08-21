#pragma once

#include <cstdint>
#include <vector>

class Device;

class Bus
{
public:

    void mapDevice(Device* device, uint32_t start, uint32_t end);

    uint8_t read(uint32_t address);
    void write(uint32_t address, uint8_t value);

    bool isMapped(uint32_t address);

    void tick();

    bool pollInterrupt();

private:

    struct MappedDevice
    {
        Device* device;
        uint32_t start;
        uint32_t end;
    };

    std::vector<MappedDevice> devices;

    MappedDevice* findDevice(uint32_t address);
};
