#include "Timer.h"

Timer::Timer()
{
    counter = 0;
    compare = 0;
    enabled = false;
    pending = false;
}

uint8_t Timer::read(uint32_t address)
{
    switch (address)
    {
    case 0: return counter & 0xFF;
    case 1: return counter >> 8;
    case 2: return compare & 0xFF;
    case 3: return compare >> 8;

    case 4:
        return (enabled ? 0x01 : 0) | (pending ? 0x02 : 0);

    default:
        return 0;
    }
}

void Timer::write(uint32_t address, uint8_t value)
{
    switch (address)
    {
    case 0:
    case 1:
        counter = 0;
        break;

    case 2:
        compare = (compare & 0xFF00) | value;
        break;

    case 3:
        compare = (compare & 0x00FF) | (static_cast<uint16_t>(value) << 8);
        break;

    case 4:
        // Любая запись в регистр управления подтверждает
        // (сбрасывает) прерывание, а бит 0 включает/выключает таймер
        enabled = (value & 0x01) != 0;
        pending = false;
        break;

    default:
        break;
    }
}

void Timer::tick()
{
    counter++;

    if (enabled && compare != 0 && counter >= compare)
    {
        counter = 0;
        pending = true;
    }
}

bool Timer::interruptPending()
{
    return pending;
}
