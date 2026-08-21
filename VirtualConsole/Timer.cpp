#include "Timer.h"

Timer::Timer()
{
    counter = 0;
}

uint8_t Timer::read(uint16_t address)
{
    switch (address)
    {
    case 0: return counter & 0xFF;
    case 1: return counter >> 8;

    default:
        return 0;
    }
}

void Timer::write(uint16_t, uint8_t)
{
    counter = 0;
}

void Timer::tick()
{
    counter++;
}
