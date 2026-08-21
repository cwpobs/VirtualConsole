#include "Keyboard.h"

#include <conio.h>

Keyboard::Keyboard()
{
    head = 0;
    tail = 0;
    count = 0;

    enabled = false;
    pending = false;
}

bool Keyboard::queueEmpty()
{
    return count == 0;
}

bool Keyboard::queueFull()
{
    return count == QUEUE_SIZE;
}

void Keyboard::queuePush(uint8_t value)
{
    if (queueFull())
    {
        // Буфер переполнен - новая клавиша теряется
        return;
    }

    queue[tail] = value;
    tail = (tail + 1) % QUEUE_SIZE;
    count++;
}

uint8_t Keyboard::queuePop()
{
    if (queueEmpty())
    {
        return 0;
    }

    uint8_t value = queue[head];
    head = (head + 1) % QUEUE_SIZE;
    count--;

    return value;
}

uint8_t Keyboard::read(uint16_t address)
{
    switch (address)
    {
    case 0:
        return queuePop();

    case 1:
        return
            (enabled ? 0x01 : 0) |
            (pending ? 0x02 : 0) |
            (queueEmpty() ? 0 : 0x04);

    default:
        return 0;
    }
}

void Keyboard::write(uint16_t address, uint8_t value)
{
    switch (address)
    {
    case 1:
        // Любая запись в регистр управления подтверждает
        // (сбрасывает) прерывание, а бит 0 включает/выключает клавиатуру
        enabled = (value & 0x01) != 0;
        pending = false;
        break;

    default:
        break;
    }
}

void Keyboard::tick()
{
    if (_kbhit())
    {
        int key = _getch();

        queuePush(static_cast<uint8_t>(key));

        if (enabled && !queueEmpty())
        {
            pending = true;
        }
    }
}

bool Keyboard::interruptPending()
{
    return pending;
}
