#include "Bus.h"
#include "Device.h"

void Bus::mapDevice(Device* device, uint32_t start, uint32_t end)
{
    devices.push_back({ device, start, end });
}

void Bus::registerTickable(Device* device)
{
    tickableDevices.push_back(device);
}

Bus::MappedDevice* Bus::findDevice(uint32_t address)
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

uint8_t Bus::read(uint32_t address)
{
    MappedDevice* mapped = findDevice(address);

    if (mapped == nullptr)
    {
        return 0;
    }

    return mapped->device->read(address - mapped->start);
}

void Bus::write(uint32_t address, uint8_t value)
{
    MappedDevice* mapped = findDevice(address);

    if (mapped == nullptr)
    {
        return;
    }

    mapped->device->write(address - mapped->start, value);
}

bool Bus::isMapped(uint32_t address)
{
    return findDevice(address) != nullptr;
}

void Bus::tick()
{
    for (Device* device : tickableDevices)
    {
        device->tick();
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
