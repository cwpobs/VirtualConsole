#include "Mouse.h"

#include <algorithm>
#include <cstdlib>

Mouse::Mouse()
{
    accumDx = 0;
    accumDy = 0;
    buttons = 0;
    captureEnabled = false;
}

uint8_t Mouse::clampMagnitude(int value)
{
    int mag = std::abs(value);
    return static_cast<uint8_t>(std::min(mag, 127));
}

uint8_t Mouse::read(uint32_t address)
{
    std::lock_guard<std::mutex> lock(stateMutex);

    switch (address)
    {
    case REG_DELTA_X_SIGN:
        return accumDx < 0 ? 1 : 0;

    case REG_DELTA_X_MAG:
    {
        uint8_t mag = clampMagnitude(accumDx);
        accumDx = 0;
        return mag;
    }

    case REG_DELTA_Y_SIGN:
        return accumDy < 0 ? 1 : 0;

    case REG_DELTA_Y_MAG:
    {
        uint8_t mag = clampMagnitude(accumDy);
        accumDy = 0;
        return mag;
    }

    case REG_BUTTONS:
        return buttons;

    case REG_CONTROL:
        return captureEnabled ? 0x01 : 0;

    default:
        return 0;
    }
}

void Mouse::write(uint32_t address, uint8_t value)
{
    if (address == REG_CONTROL)
    {
        std::lock_guard<std::mutex> lock(stateMutex);
        captureEnabled = (value & 0x01) != 0;
    }
}

void Mouse::injectMouseMove(int dx, int dy)
{
    std::lock_guard<std::mutex> lock(stateMutex);
    accumDx += dx;
    accumDy += dy;
}

void Mouse::setButton(int buttonBit, bool down)
{
    std::lock_guard<std::mutex> lock(stateMutex);

    if (down)
    {
        buttons |= static_cast<uint8_t>(1 << buttonBit);
    }
    else
    {
        buttons &= static_cast<uint8_t>(~(1 << buttonBit));
    }
}

bool Mouse::isCaptureEnabled()
{
    std::lock_guard<std::mutex> lock(stateMutex);
    return captureEnabled;
}
