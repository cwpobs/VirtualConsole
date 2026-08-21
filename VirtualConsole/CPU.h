#pragma once

#include <cstdint>

class Bus;

class CPU
{
public:

    // =========================
    // Registers
    // =========================

    uint8_t A;
    uint8_t B;
    uint8_t C;
    uint8_t D;

    // Program Counter
    uint32_t PC;

    // Stack Pointer
    uint32_t SP;

    // Регистр-указатель для косвенной адресации (STX/LDX)
    uint32_t HL;

    // =========================
    // Flags
    // =========================

    uint8_t FLAGS;

    static const uint8_t FLAG_ZERO = 1 << 0;

    // =========================
    // State
    // =========================

    bool running;

    Bus* bus;

    // Общее количество тактов, выполненных процессором
    uint64_t cycles;

    // =========================
    // Interrupts
    // =========================

    bool interruptsEnabled;

    // Адрес, по которому должен находиться JMP на
    // реальный обработчик прерывания (см. ASSEMBLY.md).
    // Ровно сразу после первого JMP (opcode + 4-байтный адрес = 5 байт)
    static const uint32_t INTERRUPT_VECTOR = 0x00000005;

    // =========================
    // Functions
    // =========================

    void connectBus(Bus* bus);

    void reset();

    void step();

private:

    uint8_t* getRegister(uint8_t index);

    uint8_t busRead(uint32_t address);
    void busWrite(uint32_t address, uint8_t value);
};