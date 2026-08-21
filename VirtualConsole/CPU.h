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
    uint16_t PC;

    // Stack Pointer
    uint16_t SP;

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

    // =========================
    // Functions
    // =========================

    void connectBus(Bus* bus);

    void reset();

    void step();

private:

    uint8_t* getRegister(uint8_t index);
};