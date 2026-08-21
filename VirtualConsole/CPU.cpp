#include "CPU.h"
#include "Bus.h"

void CPU::connectBus(Bus* bus)
{
    this->bus = bus;
}

void CPU::reset()
{
    A = 0;
    B = 0;
    C = 0;
    D = 0;

    PC = 0;

    SP = 0xEFFF;

    FLAGS = 0;

    running = false;

    cycles = 0;
}

uint8_t CPU::busRead(uint16_t address)
{
    uint8_t value = bus->read(address);

    cycles++;
    bus->tick();

    return value;
}

void CPU::busWrite(uint16_t address, uint8_t value)
{
    bus->write(address, value);

    cycles++;
    bus->tick();
}

uint8_t* CPU::getRegister(uint8_t index)
{
    switch (index)
    {
    case 0: return &A;
    case 1: return &B;
    case 2: return &C;
    case 3: return &D;

    default:
        return nullptr;
    }
}

void CPU::step()
{
    // =========================
    // Fetch
    // =========================

    uint8_t opcode = busRead(PC);

    PC++;

    // =========================
    // Decode + Execute
    // =========================

    switch (opcode)
    {
        // -------------------------
        // LDI reg, value
        // -------------------------

    case 0x01:
    {
        uint8_t registerIndex = busRead(PC);
        PC++;

        uint8_t value = busRead(PC);
        PC++;

        uint8_t* reg = getRegister(registerIndex);

        if (reg != nullptr)
        {
            *reg = value;
        }

        break;
    }

    // -------------------------
    // LDA address
    // -------------------------

    case 0x02:
    {
        uint8_t low = busRead(PC);
        PC++;

        uint8_t high = busRead(PC);
        PC++;

        uint16_t address =
            low |
            (high << 8);

        A = busRead(address);

        break;
    }

    // -------------------------
    // STA address
    // -------------------------

    case 0x03:
    {
        uint8_t low = busRead(PC);
        PC++;

        uint8_t high = busRead(PC);
        PC++;

        uint16_t address =
            low |
            (high << 8);

        busWrite(address, A);

        break;
    }

    // -------------------------
    // ADD reg
    // -------------------------

    case 0x04:
    {
        uint8_t registerIndex = busRead(PC);
        PC++;

        uint8_t* reg = getRegister(registerIndex);

        if (reg != nullptr)
        {
            A += *reg;
        }

        break;
    }

    // -------------------------
    // SUB reg
    // -------------------------

    case 0x05:
    {
        uint8_t registerIndex = busRead(PC);
        PC++;

        uint8_t* reg = getRegister(registerIndex);

        if (reg != nullptr)
        {
            A -= *reg;
        }

        break;
    }

    // -------------------------
    // CMP reg
    // -------------------------

    case 0x06:
    {
        uint8_t registerIndex = busRead(PC);
        PC++;

        uint8_t* reg = getRegister(registerIndex);

        if (reg != nullptr)
        {
            if (A == *reg)
            {
                FLAGS |= FLAG_ZERO;
            }
            else
            {
                FLAGS &= ~FLAG_ZERO;
            }
        }

        break;
    }

    // -------------------------
    // JMP address
    // -------------------------

    case 0x07:
    {
        uint8_t low = busRead(PC);
        PC++;

        uint8_t high = busRead(PC);
        PC++;

        uint16_t address =
            low |
            (high << 8);

        PC = address;

        break;
    }

    // -------------------------
    // JZ address
    // -------------------------

    case 0x08:
    {
        uint8_t low = busRead(PC);
        PC++;

        uint8_t high = busRead(PC);
        PC++;

        uint16_t address =
            low |
            (high << 8);

        if (FLAGS & FLAG_ZERO)
        {
            PC = address;
        }

        break;
    }

    // -------------------------
    // JNZ address
    // -------------------------

    case 0x09:
    {
        uint8_t low = busRead(PC);
        PC++;

        uint8_t high = busRead(PC);
        PC++;

        uint16_t address =
            low |
            (high << 8);

        if (!(FLAGS & FLAG_ZERO))
        {
            PC = address;
        }

        break;
    }

    // -------------------------
    // PUSH reg
    // -------------------------

    case 0x0A:
    {
        uint8_t registerIndex = busRead(PC);
        PC++;

        uint8_t* reg = getRegister(registerIndex);

        if (reg != nullptr)
        {
            busWrite(SP, *reg);
            SP--;
        }

        break;
    }

    // -------------------------
    // POP reg
    // -------------------------

    case 0x0B:
    {
        uint8_t registerIndex = busRead(PC);
        PC++;

        uint8_t* reg = getRegister(registerIndex);

        if (reg != nullptr)
        {
            SP++;
            *reg = busRead(SP);
        }

        break;
    }

    // -------------------------
    // CALL address
    // -------------------------

    case 0x0C:
    {
        uint8_t low = busRead(PC);
        PC++;

        uint8_t high = busRead(PC);
        PC++;

        uint16_t address =
            low |
            (high << 8);

        busWrite(SP, (PC >> 8) & 0xFF);
        SP--;

        busWrite(SP, PC & 0xFF);
        SP--;

        PC = address;

        break;
    }

    // -------------------------
    // RET
    // -------------------------

    case 0x0D:
    {
        SP++;
        uint8_t low = busRead(SP);

        SP++;
        uint8_t high = busRead(SP);

        PC = low | (high << 8);

        break;
    }

    // -------------------------
    // HLT
    // -------------------------

    case 0xFF:
    {
        running = false;

        break;
    }

    // -------------------------
    // Unknown opcode
    // -------------------------

    default:
    {
        running = false;

        break;
    }
    }
}