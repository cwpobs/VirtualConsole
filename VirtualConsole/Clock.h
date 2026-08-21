#pragma once

#include "Device.h"

#include <chrono>
#include <cstdint>

// Часы реального времени - в отличие от Timer (чей counter растёт на
// каждое обращение к шине, см. Bus::tick()/CPU::busRead/busWrite, и
// поэтому не измеряет настоящее время, а зависит от того, сколько
// шинных операций уходит на один кадр), Clock отдаёт РЕАЛЬНО прошедшие
// миллисекунды (std::chrono::steady_clock), посчитанные прямо в
// read() - не важно, сколько раз и когда его опрашивали. Нужен для
// честной привязки анимации к реальному времени (см. C/DEMO.ASM).
class Clock : public Device
{
public:

    Clock();

    uint8_t read(uint32_t address) override;
    void write(uint32_t address, uint8_t value) override;

private:

    std::chrono::steady_clock::time_point start;

    void reset();
    uint16_t elapsedMillis() const;
};
