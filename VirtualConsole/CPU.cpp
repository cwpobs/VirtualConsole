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

    SP = 0x003FFFFF;

    HL = 0;

    FLAGS = 0;

    running = false;

    cycles = 0;

    interruptsEnabled = false;
}

uint8_t CPU::busRead(uint32_t address)
{
    uint8_t value = bus->read(address);

    cycles++;
    bus->tick();

    return value;
}

void CPU::busWrite(uint32_t address, uint8_t value)
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
    // Interrupt check
    // =========================

    if (interruptsEnabled && bus->pollInterrupt())
    {
        busWrite(SP, (PC >> 24) & 0xFF);
        SP--;

        busWrite(SP, (PC >> 16) & 0xFF);
        SP--;

        busWrite(SP, (PC >> 8) & 0xFF);
        SP--;

        busWrite(SP, PC & 0xFF);
        SP--;

        busWrite(SP, FLAGS);
        SP--;

        interruptsEnabled = false;
        PC = INTERRUPT_VECTOR;

        return;
    }

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
        uint8_t b0 = busRead(PC);
        PC++;

        uint8_t b1 = busRead(PC);
        PC++;

        uint8_t b2 = busRead(PC);
        PC++;

        uint8_t b3 = busRead(PC);
        PC++;

        uint32_t address =
            b0 |
            (b1 << 8) |
            (b2 << 16) |
            (static_cast<uint32_t>(b3) << 24);

        A = busRead(address);

        break;
    }

    // -------------------------
    // STA address
    // -------------------------

    case 0x03:
    {
        uint8_t b0 = busRead(PC);
        PC++;

        uint8_t b1 = busRead(PC);
        PC++;

        uint8_t b2 = busRead(PC);
        PC++;

        uint8_t b3 = busRead(PC);
        PC++;

        uint32_t address =
            b0 |
            (b1 << 8) |
            (b2 << 16) |
            (static_cast<uint32_t>(b3) << 24);

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
        uint8_t b0 = busRead(PC);
        PC++;

        uint8_t b1 = busRead(PC);
        PC++;

        uint8_t b2 = busRead(PC);
        PC++;

        uint8_t b3 = busRead(PC);
        PC++;

        uint32_t address =
            b0 |
            (b1 << 8) |
            (b2 << 16) |
            (static_cast<uint32_t>(b3) << 24);

        PC = address;

        break;
    }

    // -------------------------
    // JZ address
    // -------------------------

    case 0x08:
    {
        uint8_t b0 = busRead(PC);
        PC++;

        uint8_t b1 = busRead(PC);
        PC++;

        uint8_t b2 = busRead(PC);
        PC++;

        uint8_t b3 = busRead(PC);
        PC++;

        uint32_t address =
            b0 |
            (b1 << 8) |
            (b2 << 16) |
            (static_cast<uint32_t>(b3) << 24);

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
        uint8_t b0 = busRead(PC);
        PC++;

        uint8_t b1 = busRead(PC);
        PC++;

        uint8_t b2 = busRead(PC);
        PC++;

        uint8_t b3 = busRead(PC);
        PC++;

        uint32_t address =
            b0 |
            (b1 << 8) |
            (b2 << 16) |
            (static_cast<uint32_t>(b3) << 24);

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
        uint8_t b0 = busRead(PC);
        PC++;

        uint8_t b1 = busRead(PC);
        PC++;

        uint8_t b2 = busRead(PC);
        PC++;

        uint8_t b3 = busRead(PC);
        PC++;

        uint32_t address =
            b0 |
            (b1 << 8) |
            (b2 << 16) |
            (static_cast<uint32_t>(b3) << 24);

        busWrite(SP, (PC >> 24) & 0xFF);
        SP--;

        busWrite(SP, (PC >> 16) & 0xFF);
        SP--;

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
        uint8_t r0 = busRead(SP);

        SP++;
        uint8_t r1 = busRead(SP);

        SP++;
        uint8_t r2 = busRead(SP);

        SP++;
        uint8_t r3 = busRead(SP);

        PC =
            r0 |
            (r1 << 8) |
            (r2 << 16) |
            (static_cast<uint32_t>(r3) << 24);

        break;
    }

    // -------------------------
    // EI
    // -------------------------

    case 0x0E:
    {
        interruptsEnabled = true;

        break;
    }

    // -------------------------
    // DI
    // -------------------------

    case 0x0F:
    {
        interruptsEnabled = false;

        break;
    }

    // -------------------------
    // RETI
    // -------------------------

    case 0x10:
    {
        SP++;
        FLAGS = busRead(SP);

        SP++;
        uint8_t r0 = busRead(SP);

        SP++;
        uint8_t r1 = busRead(SP);

        SP++;
        uint8_t r2 = busRead(SP);

        SP++;
        uint8_t r3 = busRead(SP);

        PC =
            r0 |
            (r1 << 8) |
            (r2 << 16) |
            (static_cast<uint32_t>(r3) << 24);

        interruptsEnabled = true;

        break;
    }

    // -------------------------
    // LDHL value
    // -------------------------

    case 0x11:
    {
        uint8_t b0 = busRead(PC);
        PC++;

        uint8_t b1 = busRead(PC);
        PC++;

        uint8_t b2 = busRead(PC);
        PC++;

        uint8_t b3 = busRead(PC);
        PC++;

        HL =
            b0 |
            (b1 << 8) |
            (b2 << 16) |
            (static_cast<uint32_t>(b3) << 24);

        break;
    }

    // -------------------------
    // STX (store A at [HL])
    // -------------------------

    case 0x12:
    {
        busWrite(HL, A);

        break;
    }

    // -------------------------
    // LDX (load A from [HL])
    // -------------------------

    case 0x13:
    {
        A = busRead(HL);

        break;
    }

    // -------------------------
    // INCHL
    // -------------------------

    case 0x14:
    {
        HL++;

        break;
    }

    // -------------------------
    // DECHL
    // -------------------------

    case 0x15:
    {
        HL--;

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
