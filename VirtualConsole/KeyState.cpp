#include "KeyState.h"

KeyState::KeyState()
{
    mask = 0;
}

uint8_t KeyState::read(uint32_t address)
{
    if (address == 0)
    {
        std::lock_guard<std::mutex> lock(maskMutex);
        return mask;
    }

    return 0;
}

void KeyState::write(uint32_t address, uint8_t value)
{
    // Только для чтения с CPU - пишет исключительно setKeyDown() из
    // потока окна.
    (void)address;
    (void)value;
}

void KeyState::setKeyDown(uint8_t bit, bool down)
{
    std::lock_guard<std::mutex> lock(maskMutex);

    if (down)
    {
        mask |= bit;
    }
    else
    {
        mask &= static_cast<uint8_t>(~bit);
    }
}
