#include "Keyboard.h"

#include <conio.h>

Keyboard::Keyboard()
{
    head = 0;
    tail = 0;
    count = 0;

    enabled = false;
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

uint8_t Keyboard::read(uint32_t address)
{
    switch (address)
    {
    case 0:
        return queuePop();

    case 1:
        return
            (enabled ? 0x01 : 0) |
            (queueEmpty() ? 0 : 0x02);

    default:
        return 0;
    }
}

void Keyboard::write(uint32_t address, uint8_t value)
{
    switch (address)
    {
    case 1:
        // Бит 0 включает/выключает клавиатуру. Отдельного
        // подтверждения прерывания не нужно - оно само снимается,
        // когда обработчик вычитывает данные из очереди (DATA)
        enabled = (value & 0x01) != 0;
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
    }
}

bool Keyboard::interruptPending()
{
    // Уровневое прерывание: активно, пока включено и в очереди
    // есть непрочитанные данные (не защёлка, чтобы не терять
    // запросы, если в очереди накопилось несколько клавиш)
    return enabled && !queueEmpty();
}
