#pragma once

#include <cstdint>
#include <vector>

class Device;

class Bus
{
public:

    void mapDevice(Device* device, uint16_t start, uint16_t end);

    uint8_t read(uint16_t address);
    void write(uint16_t address, uint8_t value);

    bool isMapped(uint16_t address);

private:

    struct MappedDevice
    {
        Device* device;
        uint16_t start;
        uint16_t end;
    };

    std::vector<MappedDevice> devices;

    MappedDevice* findDevice(uint16_t address);
};
