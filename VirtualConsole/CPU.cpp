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
            uint16_t result = static_cast<uint16_t>(A) + *reg;

            A = static_cast<uint8_t>(result);

            if (result > 0xFF)
            {
                FLAGS |= FLAG_CARRY;
            }
            else
            {
                FLAGS &= ~FLAG_CARRY;
            }
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
            if (A < *reg)
            {
                FLAGS |= FLAG_CARRY;
            }
            else
            {
                FLAGS &= ~FLAG_CARRY;
            }

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

            if (A < *reg)
            {
                FLAGS |= FLAG_CARRY;
            }
            else
            {
                FLAGS &= ~FLAG_CARRY;
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
    // JC address (переход, если CARRY установлен)
    // -------------------------

    case 0x21:
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

        if (FLAGS & FLAG_CARRY)
        {
            PC = address;
        }

        break;
    }

    // -------------------------
    // JNC address (переход, если CARRY не установлен)
    // -------------------------

    case 0x22:
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

        if (!(FLAGS & FLAG_CARRY))
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
    // MUL reg (A = A * reg, обрезано до 8 бит)
    // -------------------------

    case 0x16:
    {
        uint8_t registerIndex = busRead(PC);
        PC++;

        uint8_t* reg = getRegister(registerIndex);

        if (reg != nullptr)
        {
            A = static_cast<uint8_t>(A * (*reg));
        }

        break;
    }

    // -------------------------
    // DIV reg (A = A / reg, деление на 0 - no-op)
    // -------------------------

    case 0x17:
    {
        uint8_t registerIndex = busRead(PC);
        PC++;

        uint8_t* reg = getRegister(registerIndex);

        if (reg != nullptr && *reg != 0)
        {
            A = A / *reg;
        }

        break;
    }

    // -------------------------
    // MOD reg (A = A % reg, деление на 0 - no-op)
    // -------------------------

    case 0x18:
    {
        uint8_t registerIndex = busRead(PC);
        PC++;

        uint8_t* reg = getRegister(registerIndex);

        if (reg != nullptr && *reg != 0)
        {
            A = A % *reg;
        }

        break;
    }

    // -------------------------
    // AND reg
    // -------------------------

    case 0x19:
    {
        uint8_t registerIndex = busRead(PC);
        PC++;

        uint8_t* reg = getRegister(registerIndex);

        if (reg != nullptr)
        {
            A = A & *reg;
        }

        break;
    }

    // -------------------------
    // OR reg
    // -------------------------

    case 0x1A:
    {
        uint8_t registerIndex = busRead(PC);
        PC++;

        uint8_t* reg = getRegister(registerIndex);

        if (reg != nullptr)
        {
            A = A | *reg;
        }

        break;
    }

    // -------------------------
    // XOR reg
    // -------------------------

    case 0x1B:
    {
        uint8_t registerIndex = busRead(PC);
        PC++;

        uint8_t* reg = getRegister(registerIndex);

        if (reg != nullptr)
        {
            A = A ^ *reg;
        }

        break;
    }

    // -------------------------
    // NOT (A = ~A)
    // -------------------------

    case 0x1C:
    {
        A = ~A;

        break;
    }

    // -------------------------
    // SHL (A = A << 1)
    // -------------------------

    case 0x1D:
    {
        A = static_cast<uint8_t>(A << 1);

        break;
    }

    // -------------------------
    // SHR (A = A >> 1)
    // -------------------------

    case 0x1E:
    {
        A = A >> 1;

        break;
    }

    // -------------------------
    // ADC reg (A = A + reg + CARRY)
    // -------------------------

    case 0x1F:
    {
        uint8_t registerIndex = busRead(PC);
        PC++;

        uint8_t* reg = getRegister(registerIndex);

        if (reg != nullptr)
        {
            uint16_t carryIn = (FLAGS & FLAG_CARRY) ? 1 : 0;
            uint16_t result = static_cast<uint16_t>(A) + *reg + carryIn;

            A = static_cast<uint8_t>(result);

            if (result > 0xFF)
            {
                FLAGS |= FLAG_CARRY;
            }
            else
            {
                FLAGS &= ~FLAG_CARRY;
            }
        }

        break;
    }

    // -------------------------
    // SBC reg (A = A - reg - CARRY)
    // -------------------------

    case 0x20:
    {
        uint8_t registerIndex = busRead(PC);
        PC++;

        uint8_t* reg = getRegister(registerIndex);

        if (reg != nullptr)
        {
            uint16_t carryIn = (FLAGS & FLAG_CARRY) ? 1 : 0;
            uint16_t operand = static_cast<uint16_t>(*reg) + carryIn;

            if (static_cast<uint16_t>(A) < operand)
            {
                FLAGS |= FLAG_CARRY;
            }
            else
            {
                FLAGS &= ~FLAG_CARRY;
            }

            A = static_cast<uint8_t>(A - operand);
        }

        break;
    }

    // -------------------------
    // ADDHL regHigh, regLow (HL += (regHigh << 8) | regLow)
    // -------------------------
    //
    // Единственный способ сдвинуть HL на runtime-смещение раньше был
    // INCHL (+1 за раз) - для больших смещений (например, y*80+x на
    // экране 80x25, до 1999) это до ~2000 отдельных шагов на КАЖДОЕ
    // обращение - см. Compiler.cpp/__mc_screen_offset и ASSEMBLY.md,
    // "Мини-C" (print_char/set_color). ADDHL прибавляет 16-битное
    // значение из пары регистров за один шаг.

    case 0x23:
    {
        uint8_t highIndex = busRead(PC);
        PC++;

        uint8_t lowIndex = busRead(PC);
        PC++;

        uint8_t* highReg = getRegister(highIndex);
        uint8_t* lowReg = getRegister(lowIndex);

        uint16_t offset = 0;

        if (highReg != nullptr)
        {
            offset |= static_cast<uint16_t>(*highReg) << 8;
        }

        if (lowReg != nullptr)
        {
            offset |= *lowReg;
        }

        HL += offset;

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
