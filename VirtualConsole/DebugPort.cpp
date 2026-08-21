#include "DebugPort.h"
#include "CPU.h"

DebugPort::DebugPort(CPU* cpu)
{
    this->cpu = cpu;
}

uint8_t DebugPort::read(uint32_t address)
{
    switch (address)
    {
    case 0: return cpu->PC & 0xFF;
    case 1: return (cpu->PC >> 8) & 0xFF;
    case 2: return (cpu->PC >> 16) & 0xFF;
    case 3: return (cpu->PC >> 24) & 0xFF;

    case 4: return cpu->SP & 0xFF;
    case 5: return (cpu->SP >> 8) & 0xFF;
    case 6: return (cpu->SP >> 16) & 0xFF;
    case 7: return (cpu->SP >> 24) & 0xFF;

    case 8: return cpu->HL & 0xFF;
    case 9: return (cpu->HL >> 8) & 0xFF;
    case 10: return (cpu->HL >> 16) & 0xFF;
    case 11: return (cpu->HL >> 24) & 0xFF;

    case 12: return cpu->FLAGS;

    default: return 0;
    }
}

void DebugPort::write(uint32_t address, uint8_t value)
{
    // Только для чтения - записи игнорируются.
    (void)address;
    (void)value;
}
