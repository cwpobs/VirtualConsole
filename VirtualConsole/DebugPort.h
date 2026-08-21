#pragma once

#include "Device.h"

class CPU;

// Устройство только для чтения: даёт запущенной программе доступ
// к тем регистрам CPU, которые иначе прочитать в обычный регистр
// нельзя (PC/SP/HL/FLAGS - нет инструкции, которая бы это делала).
// Нужно для команды "regs" в терминале (см. boot.asm).
class DebugPort : public Device
{
public:

    DebugPort(CPU* cpu);

    uint8_t read(uint32_t address) override;
    void write(uint32_t address, uint8_t value) override;

private:

    CPU* cpu;
};
