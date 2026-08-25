#pragma once

#include <cstdint>
#include <vector>

class Device;

class Bus
{
public:

    void mapDevice(Device* device, uint32_t start, uint32_t end);

    // Устройства, которым реально нужен периодический tick() (Timer,
    // Keyboard - опрос реальных часов/клавиатуры) - отдельный список от
    // mapDevice(), а не "все замапленные устройства": раньше tick()
    // обходил ВСЕ устройства на шине на КАЖДЫЙ байт (см. старое место
    // вызова в CPU::busRead/busWrite) - для программы, дёргающей MMIO
    // тысячами poke() за кадр (см. Gpu3D), это давало миллионы лишних
    // вызовов tick() в секунду и заметно тормозило (см.
    // misty-zooming-bee.md). Теперь tick() вызывается раз за инструкцию
    // CPU (см. CPU::step()) и только по этому короткому списку.
    void registerTickable(Device* device);

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
    std::vector<Device*> tickableDevices;

    MappedDevice* findDevice(uint32_t address);
};
