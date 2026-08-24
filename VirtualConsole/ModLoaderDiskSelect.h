#pragma once

#include "Device.h"

// Один регистр - на каком диске искать файл при следующем ModLoader
// LOAD (см. ModLoader.h/.cpp), в дополнение к обычному резолву через
// Disk::lastExecDisk (см. ASSEMBLY.md, "ModLoader"/"Disk"). Отдельное
// маленькое устройство, а не новые регистры на самом ModLoader - у
// ModLoader уже занят весь его смежный диапазон (0xF0001020-0xF0001041),
// сразу за ним начинается ConsoleLayer (0xF0001042) - расширять некуда,
// а Bus::read/write отдают устройству адрес ОТНОСИТЕЛЬНО начала ЭТОЙ
// мапированной записи (address - mapped->start), так что повторная
// регистрация того же ModLoader на отдельном диапазоне свелась бы к
// тому же самому смещению 0, что и NAME0, - коллизия, а не новый
// регистр (см. Bus.cpp). Готовый прецедент такого же маленького
// отдельного устройства на один регистр - ConsoleLayer.
//
// Значения: 0 = не трогать (обычный резолв через Disk::lastExecDisk -
// поведение по умолчанию, полностью совместимо со всем существующим
// кодом, который этот регистр никогда не пишет), 1 = принудительно
// диск C, 2 = принудительно диск D. Никакого std::atomic не нужно (в
// отличие от ConsoleLayer) - и запись через MMIO, и чтение в
// ModLoader::load() происходят на одном и том же потоке CPU, гонки
// нет.
class ModLoaderDiskSelect : public Device
{
public:

    uint8_t read(uint32_t address) override;
    void write(uint32_t address, uint8_t value) override;

    uint8_t get() const { return value; }

private:

    uint8_t value = 0;
};
