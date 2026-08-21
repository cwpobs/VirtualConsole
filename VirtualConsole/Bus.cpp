#include "Bus.h"
#include "Device.h"

void Bus::mapDevice(Device* device, uint16_t start, uint16_t end)
{
    devices.push_back({ device, start, end });
}

Bus::MappedDevice* Bus::findDevice(uint16_t address)
{
    for (MappedDevice& mapped : devices)
    {
        if (address >= mapped.start && address <= mapped.end)
        {
            return &mapped;
        }
    }

    return nullptr;
}

uint8_t Bus::read(uint16_t address)
{
    MappedDevice* mapped = findDevice(address);

    if (mapped == nullptr)
    {
        return 0;
    }

    return mapped->device->read(address - mapped->start);
}

void Bus::write(uint16_t address, uint8_t value)
{
    MappedDevice* mapped = findDevice(address);

    if (mapped == nullptr)
    {
        return;
    }

    mapped->device->write(address - mapped->start, value);
}

bool Bus::isMapped(uint16_t address)
{
    return findDevice(address) != nullptr;
}

void Bus::tick()
{
    for (MappedDevice& mapped : devices)
    {
        mapped.device->tick();
    }
}

bool Bus::pollInterrupt()
{
    for (MappedDevice& mapped : devices)
    {
        if (mapped.device->interruptPending())
        {
            return true;
        }
    }

    return false;
}
