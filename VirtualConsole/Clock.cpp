#include "Clock.h"

Clock::Clock()
{
    reset();
}

void Clock::reset()
{
    start = std::chrono::steady_clock::now();
}

uint16_t Clock::elapsedMillis() const
{
    auto now = std::chrono::steady_clock::now();
    auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(now - start).count();
    return static_cast<uint16_t>(ms % 65536);
}

uint8_t Clock::read(uint32_t address)
{
    uint16_t ms = elapsedMillis();

    switch (address)
    {
    case 0: return ms & 0xFF;
    case 1: return (ms >> 8) & 0xFF;
    default: return 0;
    }
}

void Clock::write(uint32_t address, uint8_t value)
{
    (void)address;
    (void)value;

    reset();
}
