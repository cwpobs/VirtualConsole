**English** | [Русский](ASSEMBLY.ru.md)

# Virtual Console Assembly Language

Documentation for the virtual processor's assembler.

This document will keep growing as the virtual machine develops.

---

# 1. General information

The virtual processor is 8-bit: the general-purpose registers, the
ALU, and the data bus all operate on bytes. Memory addressing,
however, is 32-bit — addresses and pointers (`PC`/`SP`/`HL`) take up
4 bytes, which leaves room to expand memory almost without limit in
the future without changing the instruction format.

RAM size:

    4 MB (4 * 1024 * 1024 bytes)

Address space map:

| Range | Purpose |
|----------|------------|
| `0x00000000 - 0x003FFFFF` | RAM (4 MB) |
| `0xF0000000` and above | MMIO devices (see section 9) |

MMIO is deliberately placed far away from RAM — the huge gap between
them means RAM can be expanded in the future without touching or
relocating any device.

## Devices - summary

Devices attached to the bus (details on each one are in section 9):

| Device | Range | Size | Purpose |
|---|---|---|---|
| Timer | `0xF0000000-0xF0000004` | 5 B | tick counter, timer interrupt |
| Keyboard | `0xF0000005-0xF0000006` | 2 B | keypress queue, interrupt |
| Text VRAM | `0xF0000007-0xF00007D8` | 2002 B | 80x25 text, CP866 encoding |
| DebugPort | `0xF00007D9-0xF00007E5` | 13 B | `PC`/`SP`/`HL`/`FLAGS`, read-only |
| Disk C | `0xF00007E6-0xF00007F8` | 19 B | filesystem (host folder `C/`) |
| Disk D | `0xF00007F9-0xF000080B` | 19 B | filesystem (host folder `D/`) |
| TextAttr | `0xF000080C-0xF0000FDD` | 2002 B | character color 80x25 (fg/bg) |
| VideoCard | `0xF0000FDE-0xF0000FFB` | 30 B | 320x240 graphics, sprites, tiles |
| Clock | `0xF0000FFC-0xF0000FFD` | 2 B | real-time clock (ms) |
| PngLoader | `0xF0000FFE-0xF0001011` | 20 B | PNG loading (sprites/tiles) |
| MapLoader | `0xF0001012-0xF000101F` | 14 B | text tile-map loading |
| ModLoader | `0xF0001020-0xF0001041` | 34 B | `.mod` music loading (ProTracker) |
| Gpu3D | `0xF0001045-0xF0001065` | 33 B | 3D accelerator (vertices/triangles/PRESENT) |
| SoundCard | `0xF0001066-0xF000106E` | 9 B | playback (PLAY/STOP/VOLUME) + visualization (per-channel volume/ROW/ORDER_POS) |

The CPU has no clock frequency as such — it's a software interpreter
(`CPU::step()`), not real electronic circuitry, so "speed" depends
entirely on the host machine and isn't guaranteed. As a rough
reference point: during development, headless tests of this same
project measured interpreter throughput around ~6 million `step()`
calls/sec on the dev machine — this isn't a spec, just an observation
useful for sizing your own tests.

The keyboard and console output are real and host-backed: input comes
through the real console's `_getch()`, output goes to a regular
terminal with ANSI escape sequences; input/output encoding is CP866
(see `main.cpp`).


---

# 2. Registers

The processor has four general-purpose 8-bit registers:

    A
    B
    C
    D

There are also special registers:

    PC      Program Counter
    SP      Stack Pointer
    FLAGS   Flags Register


## A, B, C, D

General-purpose 8-bit registers.

Range:

    0 - 255

Example:

    LDI A, 100
    LDI B, 20


## PC

Program Counter.

A 32-bit address of the next instruction to execute.

After a normal instruction executes, PC is automatically incremented.

Jump instructions can change PC.


## SP

Stack Pointer.

32-bit. Points at the next free byte of the stack.

The stack grows downward (from higher addresses toward lower ones)
and occupies the top of RAM.

Current starting position:

    0x003FFFFF (the last byte of RAM)

`PUSH register`:

    Write register to the address SP, then SP--

`POP register`:

    SP++, then read register from the address SP


## HL

Pointer register for indirect addressing.

32-bit, used by the `STX`/`LDX` instructions as a memory address. Lets
you access memory at an address computed at run time (rather than
baked into the instruction itself, as with `LDA`/`STA`) — for example,
to write a sequence of characters into `Text VRAM`.

Initial value:

    0x00000000


## FLAGS

Flags register.

Current flags:

    Bit 0 - ZERO
    Bit 1 - CARRY

ZERO is set by the `CMP` instruction if the values are equal.

CARRY is the carry/borrow flag, needed for multi-byte arithmetic
(adding/subtracting numbers wider than one byte) and for "less
than/greater than" comparisons (in addition to "equal" from `ZERO`):

- `ADD`/`ADC`: `CARRY=1` if the sum exceeded 255 (there was overflow).
- `SUB`/`SBC`: `CARRY=1` if a borrow was needed (`A` was less than the
  subtrahend).
- `CMP`: `CARRY=1` if `A < register` (without changing `A`).

For example, after `CMP B`: `ZERO=1` means `A == B`; `CARRY=1` means
`A < B`; both clear means `A > B`. That gives a full unsigned
"less/greater/equal" comparison, not just "equal".


---

# 3. Instructions

## LDI

Load Immediate.

Load an immediate value into a register.

Syntax:

    LDI register, value

Examples:

    LDI A, 10
    LDI B, 255
    LDI C, 0xFF

Machine format:

    01 register value

Register codes:

    A = 0
    B = 1
    C = 2
    D = 3

Example:

    LDI A, 10

Machine code:

    01 00 0A


---

## LDA

Load A.

Load a value from memory into register A.

Syntax:

    LDA address

Example:

    LDA 1000

or:

    LDA 0x03E8

Machine format:

    02 b0 b1 b2 b3

The address is 32-bit, 4 bytes little-endian
(`b0` is the low byte, `b3` is the high byte).


---

## STA

Store A.

Write the contents of register A to memory.

Syntax:

    STA address

Example:

    STA 1000

Machine format:

    03 b0 b1 b2 b3

The address is 32-bit, 4 bytes little-endian.


---

## ADD

Add a register's value to A.

Syntax:

    ADD register

Examples:

    ADD B
    ADD C

Equivalent to:

    A = A + register

Sets the CARRY flag if the sum exceeded 255 (clears it otherwise) -
see `ADC` for addition with carry (multi-byte numbers). Does not
touch the ZERO flag.

Machine format:

    04 register


---

## SUB

Subtract a register's value from A.

Syntax:

    SUB register

Examples:

    SUB B
    SUB C

Equivalent to:

    A = A - register

Sets the CARRY flag if a borrow was needed (`A < register`), clears
it otherwise - see `SBC` for subtraction with borrow (multi-byte
numbers). Does not touch the ZERO flag.

Machine format:

    05 register


---

## ADC

Add a register's value and the CARRY flag to A ("add with carry").

Syntax:

    ADC register

Equivalent to:

    A = A + register + CARRY

Updates CARRY the same way as `ADD`. Needed for adding numbers wider
than one byte: add the low bytes with `ADD` (the carry lands in
CARRY), then add the high bytes with `ADC` (which accounts for that
carry).

Example of adding two 16-bit numbers (`A:C` = `A1:C1` + `A2:C2`, low
byte in `C`, high byte in `A`):

    LDI A, 244   ; low byte of the first number
    LDI B, 50    ; low byte of the second number
    ADD B        ; A = sum of low bytes, CARRY = whether it carried
    PUSH A
    POP C        ; C = low byte of the result

    LDI A, 1     ; high byte of the first number
    LDI B, 0     ; high byte of the second number
    ADC B        ; A = sum of high bytes + carry from the ADD above

Machine format:

    1F register


---

## SBC

Subtract a register's value and the CARRY flag from A ("subtract with
borrow").

Syntax:

    SBC register

Equivalent to:

    A = A - register - CARRY

Updates CARRY the same way as `SUB`. Symmetric to `ADC` - used for
subtracting multi-byte numbers (`SUB` on the low bytes first, then
`SBC` on the high bytes).

Machine format:

    20 register


---

## CMP

Compare A with another register.

Syntax:

    CMP register

Example:

    CMP B

If:

    A == B

the ZERO flag is set (and cleared otherwise).

Also sets the CARRY flag if `A < B` (and clears it otherwise) - see
section "2. Registers" (FLAGS) for the full unsigned comparison
via ZERO+CARRY.

Machine format:

    06 register


---

## MUL

Multiply A by a register's value.

Syntax:

    MUL register

Examples:

    MUL B
    MUL C

Equivalent to:

    A = A * register

The result is truncated to 8 bits (like `ADD`/`SUB` overflow) - `A`
and `register` are both 8-bit, and their product can reach up to
65025, which doesn't fit in one byte. For scores or other values that
might need more than 8 bits, you need to keep the result across
several bytes yourself.

Machine format:

    16 register


---

## DIV

Divide A by a register's value (integer division).

Syntax:

    DIV register

Examples:

    DIV B
    DIV C

Equivalent to:

    A = A / register

Division by zero is a safe no-op: `A` is left unchanged (instead of
undefined behavior or a crash).

Machine format:

    17 register


---

## MOD

Remainder of A divided by a register's value.

Syntax:

    MOD register

Examples:

    MOD B
    MOD C

Equivalent to:

    A = A % register

Division by zero is a safe no-op: `A` is left unchanged.

Machine format:

    18 register

`DIV`/`MOD` together let you get both the quotient and the remainder
of the same number - for example, to convert a number into decimal
text (see the `print_number` routine in `boot.asm`).


---

## AND

Bitwise AND between A and a register's value.

Syntax:

    AND register

Example:

    AND B

Equivalent to:

    A = A & register

Machine format:

    19 register


---

## OR

Bitwise OR between A and a register's value.

Syntax:

    OR register

Example:

    OR B

Equivalent to:

    A = A | register

Machine format:

    1A register


---

## XOR

Bitwise exclusive OR between A and a register's value.

Syntax:

    XOR register

Example:

    XOR B

Equivalent to:

    A = A ^ register

Machine format:

    1B register


---

## NOT

Bitwise negation of A (every bit is inverted).

Syntax:

    NOT

Equivalent to:

    A = ~A

Machine code:

    1C


---

## SHL

Shift Left. Shifts A one bit to the left; the high bit is lost, the
low bit is filled with zero.

Syntax:

    SHL

Equivalent to:

    A = A << 1

Machine code:

    1D


---

## SHR

Shift Right. Shifts A one bit to the right (logical shift); the low
bit is lost, the high bit is filled with zero.

Syntax:

    SHR

Equivalent to:

    A = A >> 1

Machine code:

    1E

`AND`/`OR`/`XOR`/`NOT`/`SHL`/`SHR`, like the other arithmetic
instructions (`ADD`/`SUB`/`MUL`/`DIV`/`MOD`), do not change `FLAGS` -
the `ZERO` flag is still only set by `CMP`.


---

## JMP

Unconditional jump.

Syntax:

    JMP address

Example:

    JMP 100

A label can be used instead:

    JMP loop

Machine format:

    07 b0 b1 b2 b3

The address is 32-bit, 4 bytes little-endian.


---

## JZ

Jump if Zero.

Jumps if the ZERO flag is set.

Syntax:

    JZ address

Example:

    CMP B
    JZ equal


---

## JNZ

Jump if Not Zero.

Jumps if the ZERO flag is not set.

Syntax:

    JNZ address

Example:

    CMP B
    JNZ not_equal


---

## JC

Jump if Carry.

Jumps if the CARRY flag is set.

Syntax:

    JC address

Example (jump if A < B):

    CMP B
    JC less_than

Machine format:

    21 b0 b1 b2 b3


---

## JNC

Jump if Not Carry.

Jumps if the CARRY flag is not set.

Syntax:

    JNC address

Example (jump if A >= B):

    CMP B
    JNC greater_or_equal

Machine format:

    22 b0 b1 b2 b3


---

## PUSH

Push a register's value onto the stack.

Syntax:

    PUSH register

Examples:

    PUSH A
    PUSH B

Machine format:

    0A register


---

## POP

Pop a value off the stack into a register.

Syntax:

    POP register

Examples:

    POP A
    POP B

Machine format:

    0B register

Example of saving and restoring A:

    PUSH A
    LDI A, 0
    POP A   ; A is back to its original value


---

## CALL

Call a subroutine.

Pushes the return address (the address of the instruction right after
CALL, 4 bytes) onto the stack, then jumps to the given address.

Syntax:

    CALL address

Example:

    CALL subroutine

A label can be used instead:

    CALL setD

Machine format:

    0C b0 b1 b2 b3


---

## RET

Return from a subroutine.

Pops the return address (4 bytes) off the stack, pushed there by the
CALL instruction, and jumps to it.

Syntax:

    RET

Machine code:

    0D

Example of calling and returning from a subroutine:

    CALL setD

    HLT

setD:

    LDI D, 123
    RET


---

## EI

Enable Interrupts.

Allow the processor to accept interrupts.

Syntax:

    EI

Machine code:

    0E

By default (after reset) interrupts are disabled - they must be
explicitly enabled with EI.


---

## DI

Disable Interrupts.

Prevent the processor from accepting interrupts.

Syntax:

    DI

Machine code:

    0F


---

## RETI

Return from Interrupt.

Return from an interrupt handler: pops FLAGS (1 byte) and the return
address (4 bytes, in that order) off the stack, restores them, and
re-enables interrupts (same effect as EI).

Syntax:

    RETI

Machine code:

    10

See section "10. Interrupts" - it includes an example of a complete
handler.


---

## LDHL

Load HL.

Load a 32-bit value into the HL pointer register.

Syntax:

    LDHL value

Example:

    LDHL 0xF0000007

Machine format:

    11 b0 b1 b2 b3


---

## STX

Store Indexed.

Write the contents of register A to the memory address held in HL.

Syntax:

    STX

Equivalent to:

    memory[HL] = A

Machine code:

    12


---

## LDX

Load Indexed.

Load register A with the value from the memory address held in HL.

Syntax:

    LDX

Equivalent to:

    A = memory[HL]

Machine code:

    13


---

## INCHL

Increment HL.

Increase HL by 1.

Syntax:

    INCHL

Machine code:

    14

Example: writing two characters into Text VRAM in sequence without
specifying each cell's address by hand:

    LDHL 0xF0000007

    LDI A, 72
    STX             ; VRAM[0xF0000007] = 'H'
    INCHL

    LDI A, 105
    STX             ; VRAM[0xF0000008] = 'i'
    INCHL


---

## ADDHL

Add to HL (16-bit).

Adds a 16-bit value, assembled from a pair of registers, to HL:
`HL += (regHigh << 8) | regLow`. Unlike `INCHL` (a shift of 1 per
step), this shifts by an arbitrary run-time offset in ONE step -
needed when the offset isn't known ahead of time and can be large
(an array index, an on-screen coordinate `y*80+x`, etc.), where
looping `INCHL` that many times would be too expensive.

Syntax:

    ADDHL regHigh, regLow

Machine code:

    23 <regHigh> <regLow>

where `<regHigh>`/`<regLow>` is a register code (A=0, B=1, C=2, D=3),
same as in `LDI`.

Example: shift HL by 300 (`0x012C` - high byte 1, low byte 44), using
the register pair B/C:

    LDHL 0xF0000007

    LDI B, 1
    LDI C, 44
    ADDHL B, C      ; HL = 0xF0000007 + 300

`__mc_hladd` and `__mc_screen_offset` in Mini-C are built on exactly
this instruction - the compiler accumulates the needed offset into a
register pair with plain `ADD`/`ADC` (see "Example: adding multi-byte
numbers" above) and applies it to `HL` with a single `ADDHL`, instead
of a loop of hundreds/thousands of `INCHL`s.


---

## HLT

Halt the processor.

Syntax:

    HLT

Machine code:

    FF


---

## DB

Define Byte.

Reserves one byte of data with the value `value`. This is a
pseudo-instruction - not a CPU opcode, but an instruction to the
assembler to reserve a byte of memory right in the code stream,
usually under a label.

Syntax:

    label: DB value

Example:

    quit: DB 0

Such a variable's address is computed by the same address counter as
instruction addresses - which means `DB` can never physically overlap
with code. This is the only way in this assembler to reserve data
without picking an address by hand (see also section "4. Labels"
below).

**Important**: `DB`, like subroutine labels, must be placed somewhere
normal execution never reaches (usually at the end of the file, after
the last `HLT`/`RETI`) - otherwise the processor will try to execute
that byte as an opcode.


---

# 4. Labels

Labels let you refer to program addresses by name.

Syntax:

    label:

Example:

    loop:
        JMP loop


Labels can be used in jump instructions:

    JMP loop
    JZ success
    JNZ loop


Example:

    LDI A, 10

loop:

    SUB B
    CMP C

    JNZ loop

    HLT


The assembler automatically replaces the label name with the
corresponding address.


## Data under a label (DB)

A label before `DB` gives a variable a name instead of an address:

    quit: DB 0
    ...
    STA quit
    LDA quit

`LDA`/`STA` (like `JMP`/`CALL`) accept either a label or a bare
address - using a name is more convenient and safer: the assembler
computes the address, you don't have to pick it by hand.

**Why this matters.** This assembler has no separation between code
and data (no `ORG`, no sections) - all bytes, including `DB`, land in
one continuously growing stream of addresses. If you set a variable's
address by hand (e.g. `STA 0x0102`) and the program later grows large
enough that the code reaches that address, writing to the variable
will start overwriting the program's own executable code - with
consequences that are hard to diagnose (execution "drifts" off to a
random place). Using `DB` rules this whole class of bug out entirely:
a variable's address is always computed by the same counter as
instruction addresses, so overlap is structurally impossible.

An explicitly hardcoded variable address is only justified when it's
accessed by code *outside* this program - for example, `main.cpp`
reads the fixed addresses `0x00010000`/`0x00010001`/`0x00010002`/
`0x00010003` through the `Bus` for rendering and diagnostics (see
`boot.asm`). Since `main.cpp` can't see assembler labels, such
"interface" addresses have to be fixed by hand and kept far enough
away from any likely code growth.

**A real-world case**: these addresses originally sat at `0x00001000`
(4096). When `boot.asm` grew to about 4.6 KB (after adding the
`dir`/`type`/`cd` commands), the code grew right up to that boundary,
and `boot.asm` started overwriting itself by writing to those
"interface" addresses - the terminal stopped drawing the banner
without a single assembler error (found by checking
`machineCode.size()`). The addresses were moved to `0x00010000`
(65536), with plenty of headroom.


---

# 5. Comments

Comments start with the character:

    ;

Example:

    LDI A, 10 ; Load 10 into A

Everything after `;` to the end of the line is ignored.


---

# 6. Numbers

Decimal numbers are supported:

    10
    42
    255

As are hexadecimal ones:

    0x10
    0x2A
    0xFF


---

# 7. Example program

A simple example program:

    LDI A, 10
    LDI B, 20

    ADD B

    LDI C, 30

    CMP C
    JZ success

    HLT


success:

    LDI D, 123

    HLT


Result:

    A = 30
    B = 20
    C = 30
    D = 123


---

# 8. Instruction table

The "Bytes" column is the full length of the instruction in machine
code (opcode + operands).

| Opcode | Instruction | Arguments | Bytes | Description |
|--------|-------------|-----------|------|-------------|
| 01 | LDI | register, value | 3 | Load immediate |
| 02 | LDA | address | 5 | Load A from memory |
| 03 | STA | address | 5 | Store A to memory |
| 04 | ADD | register | 2 | Add register to A |
| 05 | SUB | register | 2 | Subtract register from A |
| 06 | CMP | register | 2 | Compare A with register |
| 07 | JMP | address | 5 | Unconditional jump |
| 08 | JZ | address | 5 | Jump if ZERO |
| 09 | JNZ | address | 5 | Jump if NOT ZERO |
| 0A | PUSH | register | 2 | Push register to stack |
| 0B | POP | register | 2 | Pop register from stack |
| 0C | CALL | address | 5 | Call subroutine |
| 0D | RET | — | 1 | Return from subroutine |
| 0E | EI | — | 1 | Enable interrupts |
| 0F | DI | — | 1 | Disable interrupts |
| 10 | RETI | — | 1 | Return from interrupt |
| 11 | LDHL | value | 5 | Load HL immediate |
| 12 | STX | — | 1 | Store A at [HL] |
| 13 | LDX | — | 1 | Load A from [HL] |
| 14 | INCHL | — | 1 | Increment HL |
| 15 | DECHL | — | 1 | Decrement HL |
| 16 | MUL | register | 2 | Multiply A by register (8-bit truncated) |
| 17 | DIV | register | 2 | Divide A by register (integer) |
| 18 | MOD | register | 2 | Remainder of A / register |
| 19 | AND | register | 2 | Bitwise AND with A |
| 1A | OR | register | 2 | Bitwise OR with A |
| 1B | XOR | register | 2 | Bitwise XOR with A |
| 1C | NOT | — | 1 | Bitwise NOT of A |
| 1D | SHL | — | 1 | Shift A left by 1 |
| 1E | SHR | — | 1 | Shift A right by 1 |
| 1F | ADC | register | 2 | Add register + CARRY to A |
| 20 | SBC | register | 2 | Subtract register + CARRY from A |
| 21 | JC | address | 5 | Jump if CARRY |
| 22 | JNC | address | 5 | Jump if NOT CARRY |
| 23 | ADDHL | regHigh, regLow | 3 | HL += (regHigh << 8) \| regLow |
| FF | HLT | — | 1 | Halt CPU |

Registers `A`/`B`/`C`/`D` and the values in `LDI`/`ADD`/`SUB`/`CMP`/
`PUSH`/`POP` stay 8-bit - 32-bit addressing only applies to
addresses/pointers (`LDA`/`STA`/`JMP`/`JZ`/`JNZ`/`CALL`/`LDHL`), not
to data.


---

# 9. Devices on the bus (Memory-Mapped I/O)

Besides RAM, other devices can be attached to the processor through
the bus (Bus). Each device occupies its own address range.

Current address space map:

| Address range | Device |
|-------------------|------------|
| 0x00000000 - 0x003FFFFF | Memory (RAM, 4 MB) |
| 0xF0000000 - 0xF0000004 | Timer |
| 0xF0000005 - 0xF0000006 | Keyboard |
| 0xF0000007 - 0xF00007D8 | Text VRAM (grid + SCROLL + CLEAR) |
| 0xF00007D9 - 0xF00007E5 | DebugPort (PC/SP/HL/FLAGS, read-only) |
| 0xF00007E6 - 0xF00007F8 | Disk C (folder "C" next to the exe) |
| 0xF00007F9 - 0xF000080B | Disk D (folder "D" next to the exe) |
| 0xF000080C - 0xF0000FDD | TextAttr (character/background color + SCROLL + CLEAR) |
| 0xF0000FDE - 0xF0000FFB | VideoCard (320x240 bitmap mode, 16 sprites, tiles+scroll) |
| 0xF0000FFC - 0xF0000FFD | Clock (real-time clock, std::chrono) |
| 0xF0000FFE - 0xF0001011 | PngLoader (decodes PNG into sprites/tiles) |
| 0xF0001012 - 0xF000101F | MapLoader (text tile map) |
| 0xF0001020 - 0xF0001041 | ModLoader (parses `.mod` files) |
| 0xF0001042 - 0xF0001044 | unused gap (old SoundCard location - see below) |
| 0xF0001045 - 0xF0001065 | Gpu3D (vertices/triangles/PRESENT) |
| 0xF0001066 - 0xF000106E | SoundCard (PLAY/STOP/PAUSE/RESUME, VOLUME, visualization) |

MMIO is placed far from RAM (starting at `0xF0000000`) rather than
right after its current end - this way RAM can be expanded in the
future without touching or relocating any device. The ranges don't
overlap, so the order devices are registered on the bus doesn't
matter.

## Timer

Counts ticks. One tick happens on every bus access the processor
makes (reading an opcode, an operand, or accessing memory/a device),
not per instruction.

Different instructions take a different number of ticks, depending on
how many bytes they read/write:

| Instruction | Ticks |
|------------|--------|
| LDI | 3 |
| LDA | 6 |
| STA | 6 |
| ADD | 2 |
| SUB | 2 |
| CMP | 2 |
| JMP | 5 |
| JZ | 5 |
| JNZ | 5 |
| PUSH | 3 |
| POP | 3 |
| CALL | 9 |
| RET | 5 |
| EI | 1 |
| DI | 1 |
| RETI | 6 |
| LDHL | 5 |
| STX | 2 |
| LDX | 2 |
| INCHL | 1 |
| DECHL | 1 |
| ADDHL | 3 |
| MUL | 2 |
| DIV | 2 |
| MOD | 2 |
| AND | 2 |
| OR | 2 |
| XOR | 2 |
| NOT | 1 |
| SHL | 1 |
| SHR | 1 |
| ADC | 2 |
| SBC | 2 |
| JC | 5 |
| JNC | 5 |
| HLT | 1 |

`LDA`/`STA`/`JMP`/`JZ`/`JNZ`/`CALL`/`LDHL` became more expensive than
they were under 16-bit addressing (it used to be `LDA/STA`=4,
`JMP/JZ/JNZ/LDHL`=3, `CALL`=5, `RET`=3, `RETI`=4) - the address is now
4 bytes instead of 2.

Entering an interrupt (see section 10) isn't an assembler instruction,
but it also costs ticks: 5 ticks (writing 4 bytes of PC and 1 byte of
FLAGS to the stack).

| Address | Register | Read | Write |
|-------|---------|--------|--------|
| 0xF0000000 | COUNT_LOW | Low byte of the counter | Resets the counter to 0 |
| 0xF0000001 | COUNT_HIGH | High byte of the counter | Resets the counter to 0 |
| 0xF0000002 | CMP_LOW | Low byte of the compare threshold | Sets the low byte of the threshold |
| 0xF0000003 | CMP_HIGH | High byte of the compare threshold | Sets the high byte of the threshold |
| 0xF0000004 | CONTROL | Bit 0 = ENABLE, bit 1 = PENDING | Bit 0 of the written value = ENABLE; any write clears PENDING |

The counter is 16-bit (on its own, regardless of addressing now being
32-bit). When the timer is enabled (`ENABLE=1`) and the counter
reaches the compare threshold (`CMP`), it resets to 0 and sets the
`PENDING` flag - an interrupt request (see section 10). A threshold
of `CMP = 0` is treated as "off" (will never fire), even if
`ENABLE=1`.

Example of reading the timer's value into register A:

    LDA 0xF0000000  ; timer's low byte into A

Example of resetting the timer's counter:

    STA 0xF0000000  ; any value resets the counter

Example of setting up the timer to interrupt once every 1000 ticks:

    LDI A, 0xE8
    STA 0xF0000002      ; CMP_LOW  = 0xE8
    LDI A, 0x03
    STA 0xF0000003      ; CMP_HIGH = 0x03   (0x03E8 = 1000)
    LDI A, 1
    STA 0xF0000004      ; ENABLE = 1


## Clock

A real real-time clock (`std::chrono::steady_clock`) - unlike `Timer`
above (whose `counter` increases on every bus access, and so depends
on how many bus operations a piece of code takes rather than on real
time), `Clock` always returns the ACTUAL milliseconds elapsed since
the last reset, regardless of host speed or how often it's polled.
Needed wherever real (not "tick") timing matters - for example, the
pause between animation frames (see `C/DEMOS/DEMO.ASM`).

| Address | Register | Read | Write |
|-------|---------|--------|--------|
| 0xF0000FFC | MILLIS_LOW | Low byte of elapsed ms | Resets the clock (zeroes elapsed time) |
| 0xF0000FFD | MILLIS_HIGH | High byte of elapsed ms | Resets the clock |

The 16-bit ms value wraps around (through 0) roughly once every 65
seconds - for frame pauses (tens of milliseconds), that's more than
enough headroom.

Example - waiting for exactly 60 frames per second (~16.7 ms/frame):

    LDI A, 0
    STA 0xF0000FFC      ; reset the clock

wait_frame:

    LDA 0xF0000FFD      ; MILLIS_HIGH - guard in case of >255 ms
    LDI B, 0
    CMP B
    JNZ frame_done

    LDA 0xF0000FFC      ; MILLIS_LOW
    LDI B, 17
    CMP B
    JC wait_frame

frame_done:


## Keyboard

Reads real keypresses from the console. Each keypress goes into a
queue (16 bytes), from which the processor reads them one at a time
through the DATA register.

Keypresses land in the queue not only from the console window: while
the `VideoCard` graphics window is open (`MODE_ON`), it catches
keypresses itself (`WM_CHAR`) and puts them into the same queue -
otherwise the keyboard would "stop working" the moment the user
clicked on the graphics window and took OS focus away from the
console (`_kbhit()`/`_getch()`, which `Keyboard` uses to poll console
input, only receive keypresses while the console has focus). For an
assembly program it makes no difference - wherever a keypress came
from, it just sits in the shared queue.

| Address | Register | Read | Write |
|-------|---------|--------|--------|
| 0xF0000005 | DATA | Pop and return the next byte from the queue (0 if the queue is empty) | Ignored |
| 0xF0000006 | CONTROL | Bit 0 = ENABLE, bit 1 = HAS_DATA (queue not empty) | Bit 0 of the written value = ENABLE |

If the queue overflows (more than 16 unread keys accumulate), new
keypresses are dropped.

The keyboard interrupt is level-triggered, not edge-triggered: it's
active as long as `ENABLE=1` and the queue isn't empty, and clears
itself once the handler reads data through `DATA` (unlike `Timer`,
there's no separate acknowledgment by writing to `CONTROL`). If
several more keys land in the queue while one interrupt is being
handled, the processor will immediately get the next interrupt and
process them one after another.

Example of reading the pressed key's code into register A:

    LDA 0xF0000005

Example of enabling keyboard interrupts:

    LDI A, 1
    STA 0xF0000006      ; ENABLE = 1


## Text VRAM

An 80x25-character text screen (2000 bytes) plus a `SCROLL` register.
Each byte of the grid is one character on screen. Cell address:

    address = 0xF0000007 + y * 80 + x

where `x` is the column (0-79) and `y` is the row (0-24).

| Address | Register | Description |
|-------|---------|----------|
| 0xF0000007 - 0xF00007D6 | 80x25 grid | one byte per character (ASCII) |
| 0xF00007D7 | SCROLL | writing any value shifts the whole screen up one row, the last row is cleared |
| 0xF00007D8 | CLEAR | writing any value fills the whole grid with spaces |

Stores one byte per character (like the classic VGA text mode) - only
single-byte codes (ASCII) are supported, not UTF-8. The grid has no
interrupts or control registers besides `SCROLL` - it's a plain block
of memory you can write to and read from with `LDA`/`STA`.

Example of printing "Hi" in the top-left corner of the screen (fixed
addresses, no HL):

    LDI A, 72
    STA 0xF0000007      ; H
    LDI A, 105
    STA 0xF0000008      ; i

For sequential output (without computing each cell's address by hand)
indirect addressing via `HL`/`STX`/`INCHL` is used - see section "3.
Instructions". Example:

    LDHL 0xF0000007

    LDI A, 72
    STX             ; VRAM[0xF0000007] = 'H'
    INCHL

    LDI A, 105
    STX             ; VRAM[0xF0000008] = 'i'
    INCHL

`HL` isn't checked against going out of bounds of the grid (2000
bytes) - after 2000 writes the cursor will reach the `SCROLL` register,
and the write will scroll the screen instead of writing a character.
See the `advance_row` routine in `boot.asm` for a ready-made example
of line wrapping and scrolling.


## DebugPort

A read-only device. Gives a program access to the processor registers
that otherwise can't be read into a regular register - `PC`/`SP`/`HL`/
`FLAGS` aren't tied to any read instruction (unlike `A`/`B`/`C`/`D`,
which are always directly available to a program anyway).

| Address | Register | Description |
|-------|---------|----------|
| 0xF00007D9 - 0xF00007DC | PC | 4 bytes little-endian |
| 0xF00007DD - 0xF00007E0 | SP | 4 bytes little-endian |
| 0xF00007E1 - 0xF00007E4 | HL | 4 bytes little-endian |
| 0xF00007E5 | FLAGS | 1 byte |

Writes are ignored. Used by the `regs` terminal command (`boot.asm`)
to print the processor's state.

Example of reading the low byte of `PC`:

    LDA 0xF00007D9


## Disk

The "disk" device is physically a folder on the host machine (`C` or
`D`, next to `VirtualConsole.exe`, created automatically at startup).
Files of varying length don't fit the "address = memory byte" model,
so this is a command port (registers + a command trigger), like
`Timer`/`Keyboard`, rather than a block of memory like `Text VRAM`.
Both disks (`C`/`D`) have the same 19-byte register set, each on its
own address range.

| Offset | Register | Description |
|----------|---------|----------|
| 0-11 | NAME | File name, ASCII, up to 12 characters, zero-padded |
| 12 | COMMAND (write) | `1`=LIST_FIRST, `2`=LIST_NEXT, `3`=OPEN_READ, `4`=READ_BYTE, `5`=OPEN_WRITE, `6`=WRITE_BYTE, `7`=CLOSE, `8`=LOAD, `9`=DELETE, `10`=LOAD_SHELL, `11`=CHDIR, `12`=CHDIR_UP, `13`=LOAD_RAW, `14`=BUILD, `15`-`18`=LOAD_CHILD (levels 2-5) |
| 13 | STATUS (read) | `0`=OK, `1`=EOF/no more files, `2`=error |
| 14 | DATA | Read - the byte after `READ_BYTE`; write - the byte for `WRITE_BYTE` |
| 15-18 | SIZE (read) | Size of the open file, 4 bytes little-endian (valid after `OPEN_READ`) |

Disk C: addresses `0xF00007E6` (NAME0) - `0xF00007F8` (SIZE3).
Disk D: addresses `0xF00007F9` (NAME0) - `0xF000080B` (SIZE3).

Arbitrary nesting depth is supported: `CHDIR` (`11`) enters the folder
`NAME` (`STATUS=2` if there's no such folder), `CHDIR_UP` (`12`) goes
up EXACTLY ONE level (not straight to the root - it's a quiet no-op at
the root, like in DOS) - both change the disk's "current folder"
(`currentDir` - a `std::filesystem::path`, which handles paths of any
depth on its own), which all file commands
(`LIST_FIRST`/`OPEN_READ`/`LOAD`/...) resolve against afterward -
that's exactly why `dir`/`type`/`exec` in the terminal start
showing/finding files inside a folder right after `cd`. The only depth
limit lives in `SHELL.ASM`'s prompt (`DIR_MAX_DEPTH = 8` - for the
stack of folder names used to display `C:\A\B\...>`) - `Disk` itself
has none. `LIST_FIRST`/`LIST_NEXT` list files and folders mixed
together - a folder's name in `NAME` has a trailing `/` appended to
tell it apart from a regular file.

`LIST_FIRST`/`LIST_NEXT` iterate over the files in a folder: they put
the next file's name into NAME with `STATUS=0`, or `STATUS=1` once the
files run out.

Example of listing the files on disk C:

    LDI A, 1
    STA 0xF00007F2      ; DiskC COMMAND = LIST_FIRST

    list_loop:
        LDA 0xF00007F3      ; DiskC STATUS
        LDI B, 1
        CMP B
        JZ list_done        ; no more files

        ; ...print NAME0..NAME11 (0xF00007E6..0xF00007F1)...

        LDI A, 2
        STA 0xF00007F2      ; DiskC COMMAND = LIST_NEXT
        JMP list_loop
    list_done:

Example of reading a whole file (the name is already written into
NAME0-11):

    LDI A, 3
    STA 0xF00007F2      ; COMMAND = OPEN_READ

    read_loop:
        LDI A, 4
        STA 0xF00007F2      ; COMMAND = READ_BYTE
        LDA 0xF00007F3      ; STATUS
        LDI B, 1
        CMP B
        JZ read_done        ; EOF
        LDA 0xF00007F4      ; DATA - the next byte of the file
        ; ...do something with the byte...
        JMP read_loop
    read_done:
        LDI A, 7
        STA 0xF00007F2      ; COMMAND = CLOSE

Writing a file is symmetric: write a byte to DATA, then `COMMAND` =
`WRITE_BYTE` (`6`) - after `OPEN_WRITE` (`5`), which creates the file
(or truncates an existing one to 0 bytes).

Ready-made usage examples - the `dir`/`type` terminal commands
(`boot.asm`).

`LOAD` (`8`) is a special command: it reads `NAME` **as a text `.asm`
file** (not as binary data), assembles it with the same assembler
`main.cpp` uses for `boot.asm`, and writes the result into RAM at the
fixed address `0x00002000` (the same "sandbox" already used by
`poke`/`run`). `STATUS=0` on success (`SIZE` is the number of bytes
assembled), `STATUS=2` on error (file not found or an assembler
error - without further detail). It's then run with a plain
`CALL 0x00002000`, same as code written through `poke`. Assembling on
the processor itself (inside an 8-bit program) is out of the question -
text parsing and code generation are done by the host (`Disk` keeps
its own `Assembler` and a pointer to `Bus`). Ready-made usage
example - the `exec` terminal command (`boot.asm`).

The disk that a successful `LOAD` into the `0x00002000` sandbox last
came from (i.e. the last `exec`, NOT `LOAD_SHELL`) is remembered in
`Disk::lastExecDisk` - a static pointer shared by both `Disk`
instances (C and D). `PngLoader`/`MapLoader`/`ModLoader` (see the
corresponding sections below) use this to resolve THEIR OWN resources
(PNG/maps/`.mod`) relative to whichever disk the current program was
launched from, rather than always from disk C - that way the same
program with its resources can be run from either `C:` or `D:`.

`LOAD_SHELL` (`10`) is the same as `LOAD`, but puts the result at
address `0x00020000` (the resident home of `SHELL.ASM`, separate from
the `poke`/`run`/`exec` sandbox - otherwise they'd overwrite the
shell's own code) and does NOT touch `lastExecDisk` (this is loading
the "operating system" itself at VM startup, not a user program).

The gap between the sandbox (`0x00002000`) and the resident
`SHELL.ASM` (`0x00020000`) is the entire allowed size of an exec'd
program (~120 KiB) - `LOAD_RAW`/`LOAD` don't check the file size; if
it's exceeded, the tail of the program will overwrite the start of
the running `SHELL.ASM` while it's executing. In practice there's
plenty of room even for large Mini-C programs (see below) - but this
is a hard boundary, not a soft limit.

`DELETE` (`9`) deletes the file `NAME` (`std::filesystem::remove`).
`STATUS=0` on success, `STATUS=2` if the file didn't exist or
couldn't be deleted. Ready-made usage example - the `del` terminal
command.

`BUILD` (`14`) is like `LOAD`, but the assembled result is written NOT
to RAM but to a new file on disk: the same name as `NAME`, but with
the extension replaced by `.RUN` (`NAME.ASM` -> `NAME.RUN`; if there
was no extension, `.RUN` is simply appended). `STATUS=0` on success
(`SIZE` - how many bytes were written IN TOTAL, header + code, see
below), `STATUS=2` on error (source not found, assembler error,
couldn't create the output file). Ready-made usage example - the
`build` terminal command.

`NAME.RUN` isn't just bare machine code: the file starts with a
header - a relocation table (see `Assembler::assemble()`, its third
optional parameter `relocations`, and `Disk::readRunFile()`): 4 bytes
- the number of offsets (`uint32` LE), followed by the offsets
themselves, 4 bytes (`uint32` LE) each, RELATIVE TO THE START OF THE
CODE (i.e. right after the header). Each offset points at a 4-byte
address that the assembler obtained from a LABEL (`JMP`/`CALL`/`LDA`/
`STA`/`LDHL` targeting the program's own label/variable), not from a
numeric literal - things like `STA 0xF00007D8` (absolute device
addresses) never land in this table, since they don't depend on where
the program itself sits in memory and must never be shifted. Right
after the table comes the actual machine code. The header exists so
this `.RUN` can be safely run somewhere OTHER than where it was
assembled - see `LOAD_CHILD` below; for a normal run (`LOAD_RAW`, the
same address it was assembled for), the header is simply skipped.

`LOAD_RAW` (`13`) reads `NAME.RUN` (header + code, see `BUILD` above),
skips the header (no relocation needed - it's loaded to the same
place it was assembled for, `0x00002000`, the same sandbox as `LOAD`)
and copies ONLY the code into RAM at that address. `STATUS` behaves
like `LOAD`; `SIZE` is the size of the code alone (without the
header), unlike `BUILD`'s `SIZE`. Like `LOAD`, it updates
`Disk::lastExecDisk` - a program launched from a `.RUN` also resolves
its PNG/maps/`.mod` relative to the right disk. Ready-made usage
example - auto-running `NAME.RUN` by typing just its name at the
terminal (see `cmd_autorun` in `SHELL.ASM`) - a typed line that
doesn't match any known command is tried as `NAME.RUN` through
`LOAD_RAW`, and on success is launched exactly like `exec` - without
an explicit command, like a `.exe`/`.com` in DOS.

`LOAD_CHILD` (`15`-`18`, one command per nesting level - see "Running
a child program: exec_child()" in the Mini-C section) launches an
already-built `NAME.RUN` (assembled by `BUILD` for `0x00002000`) FROM
INSIDE an already-running program (rather than from the shell), at a
SEPARATE address for each level (`Disk::EXEC_CHILD_DEPTH2..5_ADDRESS`
- `0x00100000`/`0x00140000`/`0x00180000`/`0x001C0000`). It's needed
because the currently running program (say, the file manager `FM.MC`)
itself lives at address `0x00002000` - if the child program were
loaded there too, the load would overwrite the very code that's
executing at that moment; and if every nesting level shared the same
address, the second level would just as surely overwrite the first.

Unlike `LOAD_RAW`, simply skipping the header isn't enough here:
`NAME.RUN` was assembled on the assumption that it would run at
`0x00002000` - all its own `JMP`/`CALL`/`LDA`/`STA` targeting its own
labels/variables reflect that as absolute addresses. `LOAD_CHILD` uses
the relocation table from the header (see `BUILD` above), shifts each
recorded offset's corresponding 4-byte address by the difference
between the level's address and `0x00002000`, and only then writes
the patched bytes into RAM. If `NAME.RUN` isn't found - `STATUS=2`,
refusal - no guessing here.

RAM is 4 MiB (`0x00000000`-`0x003FFFFF`, see `main.cpp`) - the nesting
level addresses live in a separate region well above
`SHELL_LOAD_ADDRESS` (`0x00020000`), crowding neither it nor each
other: 256 KiB per level (with plenty of headroom - the largest
program in the project, `FM.MC`, weighs in at around 20 KB), 4 levels
take up 1 MiB, leaving 2+ MiB of RAM completely free. Like the main
sandbox, size isn't checked at run time. These commands are **never
called directly** by programs - the decision of which one to send and
which address to call is entirely up to `SHELL.ASM`
(`shell_exec_child`, see "Mini-C" below) - ready-made usage example:
`FM.MC`, pressing `Enter` on a `*.RUN` file.

The file name (`NAME`) can be 1 to 12 characters - a full 8.3 format
(`NAME.EXTENSION`, but without a forced dot, just up to 12 bytes).
Terminal commands (`type`/`exec`/`create`/`del`/`copy`) accept it at
variable length thanks to the `CARRY` flag (see section "2.
Registers") - before `CARRY` existed, there used to be a forced
"exactly 7 characters, space-padded" limit.


## TextAttr

The color-attribute plane - a separate device, not built into
`Text VRAM` (to avoid touching the addresses already occupied by
`Text VRAM`/`DebugPort`/the disks). The same 80x25 grid as `Text VRAM`,
but the byte means color rather than a character: the low nibble
(bits 0-3) is the character color (0-15), the high nibble (bits 4-7)
is the background color (0-15). The palette is the standard 16-color
ANSI one: `0`-`7` are the regular colors (black, red, green, yellow,
blue, magenta, cyan, white), `8`-`15` are the bright versions of the
same colors.

| Offset | Register | Description |
|----------|---------|----------|
| 0-1999 | 80x25 grid | one color byte per the same cell as in `Text VRAM` |
| 2000 | SCROLL | shifts colors up one row, like `Text VRAM` |
| 2001 | CLEAR | resets the whole grid to the default color (`0x07`) |

Addresses: `0xF000080C` (first cell) - `0xF0000FDB` (last cell),
`SCROLL` = `0xF0000FDC`, `CLEAR` = `0xF0000FDD`.

Indexing is identical to `Text VRAM` (`index = y * 80 + x`) - cell
`(x, y)` sits at the same relative offset in both devices, just with
different base addresses. **Important**: when scrolling or clearing
`Text VRAM`, you need to apply `SCROLL`/`CLEAR` to `TextAttr` too -
otherwise the color "lags behind" the text (this is exactly what
`advance_row`/`cmd_cls`/`cmd_reset` in `boot.asm` do).

The whole grid's default color at startup is `0x07` (light gray on
black, DOS classic).

Example: coloring the whole row `row` bright cyan on black (`0x0E`) -
the `goto_attr_row_start` routine in `boot.asm` (like
`goto_row_start`, but based on `TextAttr`) computes the needed
address, then it's just `STX`/`INCHL` 80 times (the ready-made
`print_char_n` routine):

    LDI A, <row>
    STA row
    CALL goto_attr_row_start   ; HL = 0xF000080C + row*80
    LDI A, 80
    STA tmp2
    LDI A, 0x0E                ; color
    CALL print_char_n

Ready-made usage example - the border around the banner in
`draw_banner` (`boot.asm`).


---

## VideoCard

A 320x240 bitmap video mode, RGB (3 bytes per pixel). Unlike
`Text VRAM`/`TextAttr`, the framebuffer is NOT addressed byte-by-byte
over the bus (320*240*3 = 230400 bytes - writing them one at a time
from the CPU would be impractically slow). Instead there's a compact
command protocol (registers + a `COMMAND` trigger), like `Disk`: the
whole framebuffer lives inside the device on the C++ side.

It draws not into the console but into a separate native window
(Win32 + OpenGL/WGL) - the console keeps working as a normal text
terminal the whole time. The window and its message pump/render loop
live on a separate thread, completely independent of the CPU loop -
no rendering happens inside the device's `tick()` (`VideoCard`
doesn't even override `tick()`), since `tick()` is called on EVERY
bus access (see `CPU::busRead`/`busWrite`) - doing heavy work there
would repeat the old `Keyboard` bug (see "Keyboard" above), only much
worse.

Coordinates 0-319/0-239 don't fit in one byte (max 255) - they're
passed as LOW+HIGH bytes (16-bit), the same way `Disk` does for
`fileSize`.

| Offset | Register | Description |
|----------|---------|----------|
| 0 | X_LOW | X, low byte |
| 1 | X_HIGH | X, high byte |
| 2 | Y_LOW | Y, low byte |
| 3 | Y_HIGH | Y, high byte |
| 4 | W_LOW | width (for FILL_RECT), low byte |
| 5 | W_HIGH | width, high byte |
| 6 | H_LOW | height (for FILL_RECT), low byte |
| 7 | H_HIGH | height, high byte |
| 8 | R | color component, 0-255 |
| 9 | G | color component, 0-255 |
| 10 | B | color component, 0-255 |
| 11 | COMMAND (write = trigger) | 1=MODE_ON, 2=MODE_OFF, 3=CLEAR, 4=SET_PIXEL, 5=FILL_RECT |
| 12 | STATUS (read-only) | 0=ok, 1=coordinate/size out of screen bounds (0-319/0-239) |

Addresses: `0xF0000FDE` (X_LOW) - `0xF0000FEA` (STATUS) - background
registers; the sprite register block (see "Hardware sprites" below)
follows immediately after.

Commands (`COMMAND`):

- **1 (MODE_ON)** - opens the window (640x480, 2x scale from the
  320x240 buffer) and starts the render thread if it isn't running
  yet. Doesn't block the calling program.
- **2 (MODE_OFF)** - stops the render thread and closes the window.
  The in-memory framebuffer isn't cleared. The user closing the
  window (the X button) also puts the device into this state on its
  own - an explicit `MODE_OFF` before the program exits is still
  recommended, so the thread isn't left hanging if the window is
  still open.
- **3 (CLEAR)** - fills the whole framebuffer with color `R,G,B`
  (ignores X/Y/W/H).
- **4 (SET_PIXEL)** - colors a single pixel `(X, Y)` with `R,G,B`.
- **5 (FILL_RECT)** - fills the rectangle `X,Y,W,H` with color `R,G,B`
  in one call (no loop needed on the assembly side) - use this
  instead of looping `SET_PIXEL` for large areas (faster and an order
  of magnitude less code).

Example - fill the whole screen blue:

    LDI A, 0
    STA 0xF0000FE6      ; R = 0
    STA 0xF0000FE7      ; G = 0
    LDI A, 255
    STA 0xF0000FE8      ; B = 255
    LDI A, 3
    STA 0xF0000FE9      ; COMMAND = CLEAR

A full working example with motion, edge bouncing, and color changes -
`C/DEMOS/DEMO.ASM` (run it from the shell: `cd demos`, then
`exec demo.asm` - see "Disk" about `cd` and ModLoader/PngLoader/
MapLoader about why demo resources resolve from the CURRENT folder).
It also demonstrates the trick of turning an 8-bit "unit" coordinate
into a real 16-bit pixel via `ADD A, A` (`A = A*2`, `CARRY` = the
result's high bit) - see `ADD`/`ADC` above for this trick.

### Hardware sprites

16 independent 32x32 bitmaps (RGB), each with its own position and
visibility - the video card overlays them onto the background itself
during rendering (on the render thread, see above), without redrawing
the background underneath them and without manually erasing the old
position from assembly, unlike `SET_PIXEL`/`FILL_RECT`.

Transparency works via a chroma key: a sprite pixel with color
`(255, 0, 255)` (magenta) is treated as transparent and isn't drawn
during compositing. The only consequence is that you can't draw an
opaque pixel of exactly that color inside a sprite.

The registers continue the `VideoCard` address block (offsets 13-25,
right after `STATUS`):

| Offset | Register | Description |
|----------|---------|----------|
| 13 | SPRITE_INDEX | which sprite (0-15) the registers below refer to |
| 14 | SPRITE_PIXEL_LOW | pixel index within the sprite (0-1023), low byte |
| 15 | SPRITE_PIXEL_HIGH | pixel index, high byte |
| 16 | SPRITE_X_LOW | sprite's screen X, low byte |
| 17 | SPRITE_X_HIGH | X, high byte |
| 18 | SPRITE_Y_LOW | sprite's screen Y, low byte |
| 19 | SPRITE_Y_HIGH | Y, high byte |
| 20 | SPRITE_VISIBLE | 0/1 - whether to show the sprite |
| 21 | SPRITE_R | color component for writing a sprite pixel |
| 22 | SPRITE_G | color component |
| 23 | SPRITE_B | color component |
| 24 | SPRITE_COMMAND (write = trigger) | 1=WRITE_PIXEL, 2=CLEAR |
| 25 | SPRITE_STATUS (read-only) | 0=ok, 1=sprite/pixel index out of range |

`SPRITE_X_LOW/HIGH`, `SPRITE_Y_LOW/HIGH`, and `SPRITE_VISIBLE` take
effect immediately on write, with no command - moving a sprite every
frame should be cheap (a few `STA`s, no extra command byte).

Commands (`SPRITE_COMMAND`):

- **1 (WRITE_PIXEL)** - writes `SPRITE_R/G/B` into pixel
  `SPRITE_PIXEL` of sprite `SPRITE_INDEX`'s bitmap, then
  auto-increments `SPRITE_PIXEL` modulo 1024 - lets you fill the
  entire bitmap in sequence with a simple loop (`STA R; STA G; STA B;
  STA COMMAND`, 1024 times), without recomputing the index by hand.
- **2 (CLEAR)** - fills the selected sprite's whole bitmap with the
  chroma key color (255,0,255), i.e. makes it fully transparent/empty.

Example - define sprite 0 as a solid red 32x32 square and show it at
point (50, 50):

    LDI A, 0
    STA 0xF0000FEB      ; SPRITE_INDEX = 0

    LDI A, 255
    STA 0xF0000FF3      ; SPRITE_R = 255
    LDI A, 0
    STA 0xF0000FF4      ; SPRITE_G = 0
    STA 0xF0000FF5      ; SPRITE_B = 0
                          ; (fill all 1024 pixels - see below)

sprite_fill_loop:
    LDI A, 1
    STA 0xF0000FF6      ; SPRITE_COMMAND = WRITE_PIXEL (auto-increments)
    ; ... repeat 1024 times (loop checking SPRITE_PIXEL_LOW/HIGH) ...

    LDI A, 50
    STA 0xF0000FEE      ; SPRITE_X_LOW = 50
    LDI A, 0
    STA 0xF0000FEF      ; SPRITE_X_HIGH = 0
    LDI A, 50
    STA 0xF0000FF0      ; SPRITE_Y_LOW = 50
    LDI A, 0
    STA 0xF0000FF1      ; SPRITE_Y_HIGH = 0
    LDI A, 1
    STA 0xF0000FF2      ; SPRITE_VISIBLE = 1

Addresses: `0xF0000FDE` (X_LOW) - `0xF0000FF7` (SPRITE_STATUS) -
background and sprites; the tile-map scroll register block (see
"Hardware tiles and scrolling" below) follows immediately after.

### Hardware tiles and scrolling

A second layer over the background (but UNDER the 3D layer and the
sprites) - a tile map: a set of repeating 32x32 tiles (a tileset, up
to 128 different tiles) and a large map of tile indices (which can be
wider/taller than the 320x240 screen) that scrolls underneath a
character sprite that stays fixed on screen. Full layer draw order on
the render thread: background (`framebuffer`) -> tiles (if a map is
loaded) -> the 3D layer (if active, see `Gpu3D` below) -> sprites -
tiles fully cover the background in the visible area, the 3D layer
covers tiles wherever it actually drew something, sprites are drawn
on top of absolutely everything (this is the UI layer - a HUD/icons
over the 3D scene).

The tileset itself is filled in through `PngLoader` (`EXTRACT_TILE`,
see below), the map itself through `MapLoader` (a text file, see
below). `VideoCard`'s only tile-related part is two 16-bit scroll
registers, continuing the address block right after the sprites:

| Offset | Register | Description |
|----------|---------|----------|
| 26 | SCROLL_X_LOW | map scroll along X, low byte |
| 27 | SCROLL_X_HIGH | high byte |
| 28 | SCROLL_Y_LOW | scroll along Y, low byte |
| 29 | SCROLL_Y_HIGH | high byte |

Takes effect immediately on write (no command, like sprite position)
and is automatically clamped to the map's bounds (`0` -
`mapWidth*32-320` for X, likewise for Y) - you can't scroll past the
edge of the map, the device clamps the value itself. Until a map is
loaded (`MapLoader` hasn't run yet), the tile layer isn't drawn at
all - old demos without tiles (`DEMO.ASM`, `SPRITES.ASM`) see no
difference.

Address: `0xF0000FF8` (SCROLL_X_LOW) - `0xF0000FFB` (SCROLL_Y_HIGH).

A full working example - `C/DEMOS/TILEDEMO.ASM` (`cd demos`, then
`exec tiledemo.asm`): the character stays fixed at the center of the
screen, the map underneath it scrolls, changing direction on a timer.


---

## PngLoader

Loads a PNG file from the CURRENT folder of WHICHEVER disk (C or D)
the currently running program was actually launched from via `exec`
(`Disk::lastExecDisk` - see "Disk" below for this static pointer,
shared by both `Disk` instances; before the first `exec` in the VM's
lifetime, disk C is used by default). The same folder that the `cd`
command changes, and that `exec`/`type`/`dir` already use - so a
program run from `C:\DEMOS` (or copied to `D:\DEMOS`) (see
`C/DEMOS/*.ASM`) finds its own resources right next to itself, on the
same disk it was launched from, with no special "the program knows
its own path" mechanism. It cuts 32x32 squares out of the image
straight into `VideoCard`'s video memory - into a sprite OR into a
tileset tile. PNG is a compressed format (zlib/deflate) - decoding it
in this CPU's assembly is out of the question, so all of the format
parsing (via `stb_image.h`) is hidden entirely on the C++ side: the
assembly side only sees commands like "load a file", "cut a region
into sprite N", and "cut a region into tile N".

| Offset | Register | Description |
|----------|---------|----------|
| 0-11 | NAME0-11 | the PNG file's name (same as `Disk`) |
| 12 | SRC_X_LOW | X of the top-left corner of the region to cut, low byte |
| 13 | SRC_X_HIGH | high byte |
| 14 | SRC_Y_LOW | Y of the region, low byte |
| 15 | SRC_Y_HIGH | high byte |
| 16 | SPRITE_INDEX | destination sprite number on `VideoCard` (0-15, for EXTRACT) |
| 17 | COMMAND (write = trigger) | 1=LOAD, 2=EXTRACT, 3=EXTRACT_TILE |
| 18 | STATUS (read-only) | 0=ok, 1=file not found/couldn't decode, 2=region outside the image, 3=invalid SPRITE_INDEX/TILE_INDEX |
| 19 | TILE_INDEX | destination tile number on `VideoCard` (0-127, for EXTRACT_TILE) |

Addresses: `0xF0000FFE` (NAME0) - `0xF0001011` (TILE_INDEX).

Commands:

- **1 (LOAD)** - decodes the file `NAME` into RGBA and caches the
  result inside the device (width/height/pixels) until the next
  `LOAD` - one `LOAD` of a spritesheet/tileset serves many subsequent
  `EXTRACT`/`EXTRACT_TILE` calls without re-decoding.
- **2 (EXTRACT)** - cuts a 32x32 square out of the cached image
  starting at `(SRC_X, SRC_Y)`, converts transparency (alpha < 128 -
  the pixel becomes `VideoCard`'s chroma-key color `(255,0,255)`,
  otherwise RGB is copied as-is - the sprite/tile model doesn't store
  alpha, only a chroma key, see "Hardware sprites" above), and writes
  the result into sprite `SPRITE_INDEX`.
- **3 (EXTRACT_TILE)** - the same thing, but writes into tile
  `TILE_INDEX` of `VideoCard`'s tileset (see "Hardware tiles and
  scrolling" above) instead of a sprite.

Example - load a spritesheet and put cell `(64, 0)` into sprite 2:

    LDI A, 83   ; 'S'
    STA 0xF0000FFE
    LDI A, 80   ; 'P'
    STA 0xF0000FFF
    ; ... the rest of the file name's letters in NAME2-11, unused ones = 0 ...

    LDI A, 1
    STA 0xF000100F      ; COMMAND = LOAD

    LDA 0xF0001010       ; STATUS - check before EXTRACT
    LDI B, 0
    CMP B
    JNZ png_error

    LDI A, 64
    STA 0xF000100A      ; SRC_X_LOW = 64
    LDI A, 0
    STA 0xF000100B      ; SRC_X_HIGH = 0
    STA 0xF000100C      ; SRC_Y_LOW = 0
    STA 0xF000100D      ; SRC_Y_HIGH = 0
    LDI A, 2
    STA 0xF000100E      ; SPRITE_INDEX = 2
    LDI A, 2
    STA 0xF000100F      ; COMMAND = EXTRACT

A full working example - `C/DEMOS/SPRITES.ASM` (`cd demos`, then
`exec sprites.asm`): loads a spritesheet, arranges several characters
as a static background, and moves one of them across the screen like
`C/DEMOS/DEMO.ASM`, only through `SPRITE_X/Y` rather than `FILL_RECT`.


---

## MapLoader

Loads a text tile-map file from the CURRENT folder of whichever disk
the `exec`'d file was launched from (see `PngLoader` above for
`Disk::lastExecDisk`), and puts it straight into `VideoCard` (see
"Hardware tiles and scrolling" above) - which tile sits in which map
cell. Parsing happens on the C++ side, for the same reasoning as
`PngLoader`'s PNG parsing: building a text parser in this CPU's
assembly for what's essentially a one-off action at program startup
wouldn't make sense.

File format - plain text: each line of the file is one row of the
map, decimal tile indices (0-127) separated by spaces, all lines the
same length (the map is a rectangle). Trailing empty lines are
ignored. Example of an 8x3 map fragment:

    0 0 0 1 1 1 0 0
    0 2 2 2 2 2 0 0
    0 2 3 3 3 2 0 0

| Offset | Register | Description |
|----------|---------|----------|
| 0-11 | NAME0-11 | name of the map's text file (same as `Disk`) |
| 12 | COMMAND (write = trigger) | 1 = LOAD |
| 13 | STATUS (read-only) | 0=ok, 1=file not found, 2=parse error (not a rectangular map, empty file, tile index outside 0-127) |

Addresses: `0xF0001012` (NAME0) - `0xF000101F` (STATUS).

Command **1 (LOAD)** reads the file `NAME`, parses it per the format
above, and replaces `VideoCard`'s current map entirely in one call
(the new map replaces the old one along with its dimensions; scroll
is reset to `(0, 0)` so it can't end up outside the new, possibly
smaller, map).

Example - load `MAP.TXT`:

    LDI A, 77   ; 'M'
    STA 0xF0001012
    LDI A, 65   ; 'A'
    STA 0xF0001013
    LDI A, 80   ; 'P'
    STA 0xF0001014
    LDI A, 46   ; '.'
    STA 0xF0001015
    LDI A, 84   ; 'T'
    STA 0xF0001016
    LDI A, 88   ; 'X'
    STA 0xF0001017
    LDI A, 84   ; 'T'
    STA 0xF0001018
    LDI A, 0
    STA 0xF0001019      ; and so on, NAME7-11 = 0

    LDI A, 1
    STA 0xF000101E      ; COMMAND = LOAD

    LDA 0xF000101F       ; STATUS
    LDI B, 0
    CMP B
    JNZ map_error

A full working example - `C/DEMOS/TILEDEMO.ASM` (`cd demos`, then
`exec tiledemo.asm`), map - `C/DEMOS/MAP.TXT`.


---

## SoundCard

Plays a tracker song that's already been parsed (see `ModLoader`
below - all `.mod` format parsing lives there, `SoundCard` only plays
the ready-made structure: samples + patterns + an order table). The
sequencer, mixer, and audio output (`winmm`/`waveOut*`) all live on a
separate `std::thread`, independent of the CPU loop - same reason as
`VideoCard`: the device's `tick()` is called on EVERY bus access (see
`CPU::busRead`/`busWrite`) - heavy work there would repeat the old
`Keyboard` bug, only much worse. `SoundCard` doesn't override `tick()`
at all.

| Offset | Register | Description |
|----------|---------|----------|
| 0 | COMMAND (write = trigger) | 1=PLAY, 2=STOP, 3=PAUSE, 4=RESUME |
| 1 | STATUS (read-only) | 0=stopped/ready, 1=playing, 2=paused, 3=no song loaded |
| 2 | VOLUME | overall volume 0-255 (default 255), takes effect immediately on write |
| 3-6 | CHANNEL0-3_VOLUME (read-only) | current per-channel volume, 0-64 (native ProTracker units, same scale as `Cxx`) |
| 7 | ROW (read-only) | current pattern row, 0-63 |
| 8 | ORDER_POS (read-only) | current position in the order table, 0-127 |

Addresses: `0xF0001066` (COMMAND) - `0xF000106E` (ORDER_POS). Note the
gap at the old location, `0xF0001042`-`0xF0001044`: this block used to
sit right there, directly before `Gpu3D`, but got too small once the
visualization registers below were added, and growing it in place
would have meant shifting `Gpu3D` and rewriting every hardcoded
address in `CUBE3D.ASM`. Moving the whole block into fresh, unused
space right after `Gpu3D` avoided that entirely - addresses on this
bus were never required to be contiguous.

### Visualization registers (CHANNEL\*\_VOLUME/ROW/ORDER_POS)

These three read-only registers mirror sequencer state that already
existed internally (each channel's current volume, the current row,
the position in the order table) but wasn't visible on the bus before
- added specifically so a program can draw a live visualizer (see
`C/DEMOS/MUSIC2.MC`) without needing any new logic in the sequencer
itself. Like `VOLUME`, they're backed by `std::atomic<uint8_t>` fields
updated once per tick from the audio thread - the CPU thread reads
them without any lock, same reasoning as `VOLUME` above. All three
read as `0` before a song is loaded or while stopped.

`CHANNEL0-3_VOLUME` is the easiest of the two to read from Mini-C: it's
4 consecutive bytes, so a mapped array (`int channelVol[4] = 0xF0001069;`)
gives runtime-indexed access to all four channels in one variable, the
same trick `SNAKE.MC` uses for its game board. `ROW`/`ORDER_POS` are
single bytes at fixed addresses, so a plain `peek()` is enough for
those.

Commands:

- **1 (PLAY)** - starts playback from the beginning of the song (if
  already playing - doesn't restart it; if paused - unpauses it).
  Does nothing and leaves `STATUS=3` if no song has been loaded via
  `ModLoader` yet.
- **2 (STOP)** - stops playback and closes the audio thread. The next
  `PLAY` will start the song over from the beginning (not from where
  it stopped - that's what `PAUSE`/`RESUME` are for).
- **3 (PAUSE)** / **4 (RESUME)** - pause/resume without resetting the
  position in the song (silence instead of audio, the sequencer
  doesn't advance while paused).

If the computer has no sound device (or it's unavailable), the
`waveOutOpen` call inside `PLAY` quietly fails: there's no playback,
but the process doesn't crash or throw an exception.

### Sequencer and effects

A tick-based sequencer, like the original ProTracker: `speed` (ticks
per row, default 6) and `tempo` (BPM, default 125) determine how long
a tick lasts (`2500 / tempo` ms), a row lasts `speed` ticks. On a new
row - a new note is triggered (a sample + a frequency from the
period, `freq = 8363 * 428 / period`, ignoring finetune - an agreed
simplification) along with volume; on every tick - effects "ride
along":

| Effect | Name | Implemented |
|---|---|---|
| `0xy` | Arpeggio | yes - cycles pitch between the base note and +x/+y semitones every tick |
| `1xx` | Portamento up | yes - period decreases by `xx*4` per tick (remembering the last non-zero `xx`) |
| `2xx` | Portamento down | yes - symmetric to `1xx` |
| `3xx` | Tone portamento | yes - slides toward the period of the last specified note, doesn't retrigger the sample |
| `Axy` | Volume slide | yes - `x`>0 raises volume by `x`/tick, otherwise lowers it by `y`/tick |
| `Cxx` | Set volume | yes |
| `Bxx` | Position jump | yes |
| `Dxx` | Pattern break | yes (`xx` - BCD row to jump to in the next pattern) |
| `Fxx` | Set speed/tempo | yes (`xx<32` - speed, `xx>=32` - tempo) |
| `4xy`,`7xy`,`9xx`,`Exy` etc. | Vibrato, tremolo, sample offset, retrigger, and others | no - the note is triggered as usual, the effect itself is silently ignored |

Panning is the classic Amiga layout: channels 0 and 3 - left, 1 and
2 - right. Looping: on reaching the end of the order table (its
length is byte 950 of the file), the sequencer jumps to the
`restart position` (byte 951) - the song plays forever, as tracker
music should, until a `STOP` arrives.

Example - start an already-loaded song and stop it on Ctrl+Q (full
working example - `C/DEMOS/MUSIC.ASM`, `cd demos` + `exec music.asm`):

    LDI A, 1
    STA 0xF0001066      ; SoundCard COMMAND = PLAY
    ...
    LDI A, 2
    STA 0xF0001066      ; SoundCard COMMAND = STOP


---

## ModLoader

Reads and parses a tracker `.mod` file from the CURRENT folder of
whichever disk the `exec`'d file was launched from (see `PngLoader`
above for `Disk::lastExecDisk`) on the C++ side, and puts the ready-
made song into `SoundCard` in one call. MOD is a binary format with
its own sequencer (samples, patterns, an order table, effects) -
parsing it in this CPU's assembly is just as unrealistic as decoding
PNG (see `PngLoader`) - the assembly side only sees a "load file"
command.

Standard ProTracker MOD is supported - 31 samples, 4 channels,
signature `M.K.`/`M!K!`/`FLT4`/`4CHN` (all four mean the same thing:
the 4-channel, 31-sample format). Other signatures (more/fewer
channels, old 15-sample Soundtracker modules, etc.) give `STATUS=2`,
they don't crash.

The file name is **32 bytes**, not 12 like `Disk`/`PngLoader`/
`MapLoader`: `.mod` file names (e.g. `space_debris.mod`, 16
characters) don't fit the 8.3 convention the other loaders follow.
`ModLoader` doesn't go through `Disk` (it reads the file itself), so
the 12-byte limit elsewhere is just those devices' own choice, not a
general rule of the bus.

| Offset | Register | Description |
|----------|---------|----------|
| 0-31 | NAME0-31 | name of the `.mod` file on disk "C" |
| 32 | COMMAND (write = trigger) | 1 = LOAD |
| 33 | STATUS (read-only) | 0=ok, 1=file not found, 2=unsupported format (not M.K./4 channels/31 samples), 3=corrupted/too-short file |

Addresses: `0xF0001020` (NAME0) - `0xF0001041` (STATUS).

Command **1 (LOAD)** reads the file `NAME`, parses it (header, 31
sample descriptors, order table, patterns, sample PCM data) and, in
one call, puts the result into `SoundCard` (fully replaces the
current song, resets the sequencer to the start - you need to
explicitly send `SoundCard.PLAY` afterward to hear it, `LOAD` doesn't
start playback itself).

Example - load `space_debris.mod` and play it:

    LDI A, 115  ; 's'
    STA 0xF0001020
    LDI A, 112  ; 'p'
    STA 0xF0001021
    ; ... the rest of the file name's letters in NAME2-15, unused ones = 0 ...

    LDI A, 1
    STA 0xF0001040      ; COMMAND = LOAD

    LDA 0xF0001041       ; STATUS
    LDI B, 0
    CMP B
    JNZ mod_error

    LDI A, 1
    STA 0xF0001066      ; SoundCard COMMAND = PLAY

A full working example - `C/DEMOS/MUSIC.ASM` (`cd demos`, then
`exec music.asm`), song - `C/DEMOS/space_debris.mod`.


---

## Gpu3D

A 3D accelerator: all the math (model/camera matrices, perspective
projection, z-buffered rasterization) lives on the C++ side. The
processor is nowhere near capable of it (it doesn't even have proper
multiplication without byte overflow, let alone trigonometry) - same
reasoning as `PngLoader`/`ModLoader`. The assembly side only sees
commands at the level of "here's a vertex", "draw a triangle", "show
the frame" - the whole 3D scene accumulates in `Gpu3D`'s OWN internal
buffer (its own 320x240 color buffer + its own z-buffer + a mask of
"touched" pixels) and is handed to `VideoCard` all at once with a
`PRESENT` command (see "Hardware tiles and scrolling" above for the
full layer order - 3D is drawn OVER the tiles, but UNDER the
sprites).

No textures - color is fixed per vertex (Gouraud shading, like on the
PS1/N64); the rasterizer linearly interpolates color and depth across
a triangle's three vertices.

| Offset | Register | Description |
|----------|---------|----------|
| 0-1 | VX_LOW/HIGH | vertex X, signed 16-bit, model units |
| 2-3 | VY_LOW/HIGH | vertex Y |
| 4-5 | VZ_LOW/HIGH | vertex Z |
| 6 | VR | vertex color, R (0-255) |
| 7 | VG | vertex color, G |
| 8 | VB | vertex color, B |
| 9 | COMMAND (write = trigger) | 1=SUBMIT_VERTEX, 2=DRAW_TRIANGLE, 3=CLEAR, 4=PRESENT |
| 10 | STATUS (read-only) | 0=ok, 1=DRAW_TRIANGLE called without 3 accumulated vertices |
| 11-16 | OBJ_X/Y/Z_LOW/HIGH | object position in the world, signed 16-bit |
| 17-22 | OBJ_YAW/PITCH/ROLL_LOW/HIGH | object rotation, degrees (signed 16-bit) |
| 23-28 | CAM_X/Y/Z_LOW/HIGH | camera position in the world |
| 29-32 | CAM_YAW/PITCH_LOW/HIGH | camera rotation (no roll) |

`OBJ_*`/`CAM_*` take effect immediately on write, with no command
(like sprite position/map scroll) - rotating an object or moving the
camera every frame should be cheap (a few `STA`s, no extra command
byte).

Addresses: `0xF0001045` (VX_LOW) - `0xF0001065` (CAM_PITCH_HIGH).

Commands:

- **1 (SUBMIT_VERTEX)** - adds the current `VX/VY/VZ/VR/VG/VB` to an
  internal triangle-vertex accumulator. Designed for exactly 3
  vertices - the calling code must send `SUBMIT_VERTEX` three times
  before every `DRAW_TRIANGLE` (like `WRITE_PIXEL` for `VideoCard`'s
  sprites/tiles, just without auto-incrementing an index - here it's
  always exactly 3 vertices per triangle).
- **2 (DRAW_TRIANGLE)** - applies the model matrix (`OBJ_*` - the
  object's translation and rotation) and the camera matrix (`CAM_*`)
  to the 3 accumulated vertices, projects them into screen
  coordinates (320x240, a fixed vertical FOV of ~70°), and
  rasterizes the triangle into `Gpu3D`'s OWN internal buffer -
  barycentric rasterization, Gouraud color interpolation, a per-pixel
  z-buffer test (only a nearer pixel overwrites a farther one). A
  triangle with even one vertex behind the camera (or closer than the
  minimum distance) is discarded entirely - there's no proper
  plane clipping in v1 (a simplification: not an issue for convex
  objects like a cube at typical demo distances). Doesn't touch
  `VideoCard` directly - only its own internal buffer.
- **3 (CLEAR)** - resets the internal z-buffer (to "infinity") and the
  "touched pixels" mask - preparation for a new frame. There's no
  need to touch the color buffer itself - pixels not hit in the new
  frame simply won't be in the mask and won't cover up whatever's
  already drawn on `VideoCard` (background/tiles) on the next
  `PRESENT`.
- **4 (PRESENT)** - in one call (`VideoCard::setThreeDLayer`) hands
  the video card a copy of the color buffer and the "touched pixels"
  mask for this frame. The first `PRESENT` turns on the 3D layer in
  the video card's frame composition - before that it's simply
  skipped, old demos without 3D (`DEMO.ASM`, `SPRITES.ASM`,
  `TILEDEMO.ASM`) see no difference.

Example - draw a single triangle (camera at `(0,0,-150)`, the
cube/object at the origin with no rotation - both are the defaults):

    LDI A, 106
    STA 0xF0001060      ; CAM_Z_LOW  (-150 in 16-bit two's complement)
    LDI A, 255
    STA 0xF0001061      ; CAM_Z_HIGH

    LDI A, 3
    STA 0xF000104E      ; COMMAND = CLEAR

    ; vertex 0: (-30,-30,0), red
    LDI A, 226
    STA 0xF0001045      ; VX_LOW
    LDI A, 255
    STA 0xF0001046      ; VX_HIGH
    ; ... similarly VY_LOW/HIGH = -30, VZ_LOW/HIGH = 0 ...
    LDI A, 255
    STA 0xF000104B      ; VR = 255
    LDI A, 0
    STA 0xF000104C      ; VG = 0
    STA 0xF000104D      ; VB = 0
    LDI A, 1
    STA 0xF000104E      ; COMMAND = SUBMIT_VERTEX

    ; ... vertices 1 and 2 the same way ...

    LDI A, 2
    STA 0xF000104E      ; COMMAND = DRAW_TRIANGLE

    LDI A, 4
    STA 0xF000104E      ; COMMAND = PRESENT

A full working example - `C/DEMOS/CUBE3D.ASM` (`cd demos`, then
`exec cube3d.asm`): a spinning colored cube (12 triangles, 2 per
face) with a UI icon on top (a sprite from `SPRITES.PNG`).


---

# 10. Interrupts

The processor supports a single interrupt request (IRQ) line, shared
by all devices on the bus. There's no priority or vector - there's
always one handler, and if there are several sources, it has to
figure out for itself which device triggered it (by polling its
registers).

## Enabling interrupts

Interrupts are disabled by default (after reset). They must be
explicitly enabled with the `EI` instruction, and can be disabled
with `DI`.

## The interrupt handler

The handler must start at the fixed address `0x00000005`. Since
execution always starts at address `0x00000000`, an application
program that uses interrupts must start with a jump table:

    JMP main
    JMP irq_handler

    main:
        ; the main program

    irq_handler:
        ; the interrupt handler
        RETI

The first 5 bytes (`JMP main` - opcode + a 4-byte address) steer
execution away from the interrupt vector to the program's real start.
The second 5 bytes (at address `0x00000005`) are `JMP irq_handler`,
which is where the processor will jump on an interrupt.

## What happens on an interrupt

Between executing instructions, the processor checks whether
interrupts are enabled and whether anything on the bus is requesting
one. If so:

1. `PC` (the address of the interrupted instruction, 4 bytes) is
   pushed onto the stack, then `FLAGS` (1 byte).
2. Interrupts are automatically disabled (as with `DI`).
3. `PC` is set to `0x00000005`.

`RETI` at the end of the handler pops `FLAGS` and `PC` off the stack
in reverse order and re-enables interrupts.

The processor does not save registers `A`, `B`, `C`, `D` - the
handler must save, via `PUSH`/`POP`, whichever registers it uses, and
restore them before `RETI`.

## Example: a timer interrupt handler

    JMP main
    JMP irq_handler

    main:

        LDI A, 0xE8
        STA 0xF0000002      ; CMP_LOW  = 0xE8
        LDI A, 0x03
        STA 0xF0000003      ; CMP_HIGH = 0x03  (threshold = 1000)
        LDI A, 1
        STA 0xF0000004      ; enable the timer

        EI

    loop:
        JMP loop

    irq_handler:

        PUSH A

        LDI A, 1
        STA 0xF0000004      ; acknowledge the interrupt, the timer stays enabled

        POP A

        RETI


---

# 11. Reserved capabilities

Video and sound are implemented - not as processor instructions, but
as MMIO devices: `VideoCard` (320x240 bitmap mode, sprites, tiles
with scrolling, a 3D layer) + `PngLoader`/`MapLoader` for video and
`Gpu3D` for 3D; `SoundCard` (a MOD player) + `ModLoader` for sound.
See section 9.


---

# 12. Mini-C

Writing complex logic directly in assembly (section 3) is painful -
there are no named variables instead of addresses, no structured
`if`/`while`, every branch is a manual `JMP`/`JZ`/`CMP`. Mini-C is a
stripped-down C-like language on top of this same assembler: the
compiler (`Compiler.h`/`.cpp`) translates Mini-C text into plain ASM
text (the same syntax used earlier in this document) and hands it to
the same `Assembler` that assembles `.asm` files - after that
everything works like a regular program: `build NAME.MC` puts
`NAME.RUN` next to it (see `BUILD`/`LOAD_RAW` in the "Disk" section),
and it can be run by its file name without the extension, like any
`.RUN`.

The language is deliberately stripped down to match what this CPU can
actually do (an 8-bit ALU, no "stack+offset" addressing for local
variables, no "register to register" instruction besides `LDHL`) -
that's not a stylistic choice, it's a direct consequence of the
instruction set in section 3.

## Types and variables

The only type is `int`, unsigned 8-bit (like the CPU registers).
Overflow silently wraps around, as it does everywhere in this
assembler.

Variables are **global only** - there's no such thing as a real local
variable with a stack frame (the CPU has no "SP+offset" addressing).
`int x;` written inside `main()`/any function or at the top level of
the file is, in both cases, the same named memory cell (`x: DB 0` in
the generated ASM) - the only difference is that inside a function you
can assign it an initial value right away: `int x = 5;`.

Fixed-size arrays - top level only:

    int arr[16];

The index is 8-bit (0-255), `arr[i]` works for both reads and writes.
Implemented with the same tricks as `cmdbuf`/`NAME` in `SHELL.ASM`:
`LDHL` to the array's base address + `INCHL` in a loop the needed
number of times (a separate routine, `__mc_hladd`, which the compiler
appends to the end of the program by itself if arrays were used at
all).

### Mapped arrays

    int row3[32] = 0xF0000007 + 80*4;

The same `int name[size]` syntax, plus an optional `= address` (the
address is also a compile-time constant, like with `poke`/`const`).
Without an initializer, the array gets its own memory as usual (`DB`
at the end of the program). With an initializer, no memory of its own
is reserved: `arr[i]` does `LDHL <address>` instead of
`LDHL <internal label>` - in other words, the array becomes a
"window" into memory that already exists (usually some device's MMIO
register).

Useful wherever `poke`/`peek` don't work because the address is only
known at run time: `poke`/`peek` rigidly require an address constant
(see "poke/peek" above) - this can be worked around IF the base
address is known ahead of time and only the offset changes, which is
exactly how every array works. Example - writing to an arbitrary cell
of a Text VRAM screen row (address `0xF0000007 + y*80 + x`, section
9): the row's base address is a constant, and `x` within the row is a
regular run-time index. Because of the 8-bit index (`arr[i]` can
never be more than 256 elements), each screen row needs its own
mapped array - a ready-made example with several rows in a row and
picking the right one with an `if` cascade is `C/DEMOS/SNAKE.MC` (see
below).

## Functions

    int add(int a, int b) {
        return a + b;
    }

Parameters are actually hidden global variables with a "mangled" name
(`add__a`, `add__b`), which the calling code fills in right before
`CALL add`. **Recursion is not supported** - a recursive call would
overwrite the outer call's parameters, since it's the same global
cell, not a fresh stack frame.

A program must contain `int main() { ... }` - execution starts there
(`JMP main` is the first instruction of the generated program,
regardless of the order functions appear in the file).
`return expression;` puts the value into `A` and does `RET` - if
`main`/a function reaches the end of its body without an explicit
`return`, the compiler inserts `LDI A, 0` + `RET` itself.

## Control structures

`if`/`else`, `while`, `for` (sugar over `while` - `for (init; cond;
post) body`, all three parts are required):

    if (x > 3) {
        x = 100;
    } else {
        x = 200;
    }

    while (i < 5) {
        sum = sum + i;
        i = i + 1;
    }

    for (i = 0; i < 4; i = i + 1) {
        sum = sum + i;
    }

## Operators

    +  -  *  /  %  &  |  ^  ~  <<  >>
    == != < > <= >=
    && ||
    =

Almost all of them map 1-to-1 onto opcodes that already exist
(`ADD`/`SUB`/`MUL`/`DIV`/`MOD`/`AND`/`OR`/`XOR`/`NOT` - section 3).
Shifts (`<<`/`>>`) are implemented as a loop of `SHL`/`SHR` (which
only shift by 1 bit on their own - section 3), so shifting by a
variable amount works, but costs more than shifting by a constant.

Comparisons (`==`/`!=`/`</`>`/`<=`/`>=`) materialize the result as
`0`/`1` in `A` via `CMP` and a pair of conditional jumps - the same
"full unsigned comparison via ZERO+CARRY" described in section 2 on
`FLAGS`. `&&`/`||` short-circuit (the right-hand operand isn't
evaluated if the left one already decided the result).

## poke/peek - direct access to memory and MMIO

    poke(address, value)   ; memory[address] = value
    peek(address)          ; return memory[address]

Lets you work with any register of any device (section 9) - the video
card, sound, disk, 3D - without dedicated wrappers in the language.

**`address` must be a compile-time constant** (a number, a `0x`
literal, or a `const`, see below, including simple arithmetic over
them computed by the compiler ahead of time) - this is a limitation
of the ISA, not the language: the CPU has no "load HL/address from a
register" instruction, `LDA`/`STA` only accept a literal or a label
resolved at assembly time (section 3, `LDA`/`STA`). There is no
physical way to put a run-time-computed address into `LDA`/`STA`.

## const

    const VRAM = 0xF0000007;

A named compile-time constant - convenient for device register
addresses instead of bare hex in every program. Takes up no memory -
wherever the name appears, the compiler substitutes the number.

## Comments

Single-line, `//` to the end of the line - like everywhere else.

## Screen builtin functions

Working with Text VRAM/TextAttr directly through `poke()` requires an
address constant (see "poke/peek" above) - that's enough for a
SPECIFIC, known-ahead-of-time screen cell, but not for "draw something
at point (x, y), where x/y are variables": the address
`0xF0000007 + y*80 + x` is then computed at run time, and
`poke`/`peek` fundamentally can't handle run-time addresses. So the
screen is the **one** exception built directly into the language
(the way `poke`/`peek` once were), rather than something the user
assembles by hand from arrays:

    clear_screen();               // clears both text and color (Text VRAM + TextAttr CLEAR)
    print_char(x, y, ch);         // prints character ch (0-255, CP866 - section 9) into cell (x, y)
    print_str(x, y, "text");      // prints a string literal starting at (x, y), no line wrapping
    set_color(x, y, fg, bg);      // color of cell (x, y): fg/bg - 0-15 (see "TextAttr", section 9)

`x` (0-79), `y` (0-24), `ch`/`fg`/`bg` are ordinary `int` expressions
- they can be variables, not just constants, which is exactly what
sets them apart from plain `poke()`. `y*80` isn't computed with a
single `MUL` (it would already overflow at `y >= 4`), but with a loop
of cheap `ADD`/`ADC` by 80 per iteration, plus one `ADDHL` at the end
to apply the resulting offset to `HL` in a single step (see section 3,
`ADDHL`) - the compiler adds this code (`__mc_screen_offset`) to the
generated program by itself if it ever encountered one of these
functions.

`print_str` is the only place in the language where a string literal
`"..."` is allowed (no escaping of special characters in v1 - only
printable ASCII bytes) - the compiler stores its contents as `DB`
data and walks it in a run-time loop, calling the same path as
`print_char` for each character and incrementing `x` by one per
character - it doesn't wrap the line itself, a new line of text needs
a separate call with a different `y`.

## Running a child program: exec_child()

    poke(0x0000000F, diskId);   // EXEC_CHILD_DISK - which disk (0=C,1=D) holds NAME
    exec_child();

Launches a `*.RUN` program FROM INSIDE an already-running program - as
a system call into the resident `SHELL.ASM`, rather than a bare jump
into a sandbox. The compiler emits `CALL 0x0000000A` - a fixed low
address that `SHELL.ASM` patches to point at its own routine,
`shell_exec_child`, at startup (the same way it patches the interrupt
vector `0x00000005` - see `SHELL.ASM::main`). The program itself
doesn't decide which address or which disk command (`15`-`18`,
`LOAD_CHILD`, see the "Disk" section) to use to load the child
`*.RUN` - it only puts `NAME` on the right disk and tells
`shell_exec_child` which disk that is, via `EXEC_CHILD_DISK`
(`0x0000000F`, `0`=C, `1`=D). Control returns here once the child
program reaches its own `RET` (guaranteed to happen at the end of any
Mini-C function, including `main()` - the compiler never generates
`HLT`).

`shell_exec_child` tracks the current nesting depth (`execDepth`, a
resident `SHELL.ASM` variable, starting at `1` - an ordinary
"shell → X" program that hasn't called `exec_child()` yet) and uses it
to pick the address and disk command for the NEXT level - up to 4
additional levels (`execDepth` `2`-`5`, see the "Disk" section,
`LOAD_CHILD`). Before entering a nested level it explicitly does `DI`
(a guarantee of known interrupt state at the call boundary) - the
child program decides for itself whether to call `EI`, and must do
`DI` before its own `RET` (see `CUBE3D.ASM`/`TILEDEMO.ASM`/
`MUSIC.ASM`). It also zeroes `lastKey` (`0x00010001`) before the
`CALL` - this is MANDATORY: a child program usually compares `lastKey`
against a key code in its own polling loop (e.g. `== 17` for Ctrl+Q,
as in `MUSIC.ASM`/`music_loop`), and without the reset it would see a
STALE value left over from a previous run (its own or someone else's)
and exit instantly, without ever waiting for a real keypress - and a
keystroke the user presses right after that, uneaten, "falls through"
to whoever called `exec_child()` (for example, `FM.MC` would also see
that same Ctrl+Q via `peek()` and exit on its own). The same logic,
for the same reason, applies in `cmd_run`/`cmd_exec_run` (a regular
`exec`/`run` from the shell, not via `exec_child()`).
Why is `LOAD_CHILD` needed at all (rather than a direct `CALL` into
the calling program's own sandbox) - because the calling program
(say, the file manager `FM.MC`) itself runs at `0x00002000` - if the
child program were loaded there too, the load would overwrite the
code that's executing at that very moment; and since every nesting
level has its own separate address (not one shared "child" address),
real multi-level nesting (program → child → grandchild → ...) just
works on its own, with no changes needed to the compiler.

Ready-made example - `C/TOOLS/FM.MC`: pressing `Enter` on a `*.RUN`
file in the list copies its name into `NAME`, puts the disk into
`EXEC_CHILD_DISK`, then calls `exec_child()`; after it returns -
`clear_screen()` and a full redraw of both panels (the child program
almost certainly used the screen for itself).

## Sound and music: mod_load()/sound_*()

    if (mod_load("space_debris.mod") != 0) { return 1; }   // STATUS: 0=ok,1=not found,2=bad format,3=corrupted
    sound_play();
    sound_stop();
    sound_pause();
    sound_resume();
    sound_set_volume(255);   // 0-255, overall volume

Ergonomic wrappers around `ModLoader`/`SoundCard` (see those sections
above) - before these existed, reaching them required raw `poke()`/
`peek()` with the literal MMIO addresses spelled out by hand.

`mod_load(string)` is the interesting one to compare against
`print_str`: `print_str` needs an actual RUNTIME loop, because its
destination coordinates (`x`, `y` in Text VRAM) can be runtime
variables. `mod_load`'s destination, by contrast, is always
`ModLoader`'s fixed `NAME0-31` range - a compile-time-constant base
address, full stop. So the compiler doesn't emit a loop at all: it
unrolls the string literal into a flat sequence of `LDI A,<byte>;
STA <address>` pairs, one pair per character, at COMPILE time,
zero-pads the rest up to 32 bytes, then emits `LDI A,1; STA
0xF0001040` (COMMAND=LOAD) and `LDA 0xF0001041` (STATUS ends up in
`A`, as the return value of the whole expression). No runtime loop
means no runtime cost beyond the fixed sequence of stores - simpler
and cheaper than `print_str`'s mechanism, not just a shorter way to
write the same thing. A literal longer than 32 characters is a
compile-time error.

`sound_play()`/`sound_stop()`/`sound_pause()`/`sound_resume()` take no
arguments - each is just `LDI A,<code>; STA 0xF0001066` (`SoundCard`
COMMAND, see above), the same pattern as `clear_screen()`.
`sound_set_volume(v)` evaluates `v` into `A` and stores it to
`0xF0001068` (`SoundCard` VOLUME) - the same pattern as `set_color()`,
just one register instead of four.

Reading the new visualization registers (`CHANNEL0-3_VOLUME`/`ROW`/
`ORDER_POS`) needs no new builtin at all - a mapped array over
`CHANNEL0-3_VOLUME` (like `SNAKE.MC`'s game board) or a plain `peek()`
for `ROW`/`ORDER_POS` already does the job, since those addresses are
themselves compile-time constants. See "SoundCard" above and
`C/DEMOS/MUSIC2.MC` below for a full example.

## What's deliberately missing in v1

- Strings as a full type (you can't store a string in a variable,
  compare it, concatenate it) - only a literal directly inside
  `print_str`.
- Pointers, `struct`, 16/32-bit types, `switch`.
- Recursion (see "Functions" above).
- Compound assignment operators (`+=` etc.) and `++`/`--` - write
  `i = i + 1;` instead.

## Example: COUNTER.MC

Ready-made example - `C/DEMOS/COUNTER.MC`: the function `sum(n)` sums
`1..n` in a loop, `main()` prints the result as three digits through
`poke()` into Text VRAM, using an intermediate array `digits[3]` and
`DIV`/`MOD` (the same trick for converting a number into decimal text
as `print_number` in `boot.asm`). Build and run:

    build counter.mc
    counter

## Example: SNAKE.MC

`C/DEMOS/SNAKE.MC` is a console Snake game that covers almost the
whole language at once: mapped arrays (the game board, one array per
screen row - see "Mapped arrays" above), regular arrays
(`snakeX`/`snakeY` - the snake's body, classic movement by shifting
the array), functions, `while`/`for`/`if`, reading the keyboard
directly via `peek(0xF0000005)` (the `Keyboard` device's `DATA`
register, section 9) - WITHOUT interrupts (Mini-C has no `EI`/`DI`
and never will - those are CPU opcodes, not an MMIO register, `poke()`
can't reach them; besides, `exec`/`run` already run with interrupts
disabled anyway - see `cmd_exec_run` in `SHELL.ASM` - so polling
`DATA` directly here isn't a workaround, it's the only thing that
works), and `Clock` for the pause between game ticks. Controls -
`W`/`A`/`S`/`D`, quit - `Ctrl+Q`. Build and run:

    build snake.mc
    snake

## Example: MUSIC2.MC

`C/DEMOS/MUSIC2.MC` plays `space_debris.mod` (`mod_load()` +
`sound_play()`) and, at the same time, draws a live 4-bar equalizer in
graphics mode (`VideoCard`, `poke(VIDEO_COMMAND, 1)` for MODE_ON) - one
bar per ProTracker channel, its height read straight from the new
`CHANNEL0-3_VOLUME` registers through a mapped array
(`int channelVol[4] = 0xF0001069;`). `VideoCard` and `SoundCard` are
independent devices with their own threads (see both sections above) -
running both from the same Mini-C program needs no special handling.
Quit - `Ctrl+Q`. Build and run:

    build music2.mc
    music2

## Cheat sheet

A compact syntax summary - without explanations (those are above, via
the links in the last column).

**Types and variables**

| Syntax | Meaning | Details |
|---|---|---|
| `int x;` | a global variable (even if written inside a function) | "Types and variables" |
| `int x = 5;` | a variable with an initial value (inside a function only) | "Types and variables" |
| `int arr[16];` | a fixed-size array, index 0-255 | "Types and variables" |
| `int arr[16] = 0xF0000007;` | a mapped array - a window into existing memory at an address | "Mapped arrays" |

**Functions**

| Syntax | Meaning |
|---|---|
| `int name(int a, int b) { ... }` | a function (no recursion - parameters are global variables) |
| `return expression;` | return a value (puts it in `A`, does `RET`) |
| `int main() { ... }` | the mandatory entry point |

**Control structures**

    if (condition) { ... } else { ... }
    while (condition) { ... }
    for (init; condition; post) { ... }

**Operators**

| Category | Operators |
|---|---|
| Arithmetic | `+` `-` `*` `/` `%` |
| Bits | `&` `\|` `^` `~` `<<` `>>` |
| Comparisons | `==` `!=` `<` `>` `<=` `>=` |
| Logic | `&&` `\|\|` (short-circuiting) |
| Assignment | `=` |

**Memory and MMIO**

| Syntax | Meaning | Details |
|---|---|---|
| `poke(address, value)` | write a byte at an address (address is a compile-time constant) | "poke/peek" |
| `peek(address)` | read a byte at an address | "poke/peek" |
| `const NAME = value;` | a named compile-time constant, takes up no memory | "const" |

**Screen (Text VRAM/TextAttr)**

| Call | What it does |
|---|---|
| `clear_screen()` | clears both text and color |
| `print_char(x, y, ch)` | character `ch` (0-255, CP866) into cell `(x, y)` |
| `print_str(x, y, "text")` | a string literal starting at `(x, y)`, no wrapping |
| `set_color(x, y, fg, bg)` | the cell's color, `fg`/`bg` - 0-15 |

**Child programs**

    poke(0x0000000F, diskId);   // EXEC_CHILD_DISK - 0=C, 1=D
    exec_child();               // run *.RUN from NAME on disk diskId, returns after its RET

See "Running a child program: exec_child()" above - up to 5 nesting
levels, zeroes `lastKey` before launching, the disk and file name in
`NAME` are prepared by the calling code beforehand.

**Sound and music**

| Call | What it does |
|---|---|
| `mod_load("name.mod")` | loads a `.mod` file into `SoundCard`, returns `STATUS` |
| `sound_play()` / `sound_stop()` | start/stop playback |
| `sound_pause()` / `sound_resume()` | pause/resume without resetting position |
| `sound_set_volume(v)` | overall volume, 0-255 |

See "Sound and music: mod_load()/sound_*()" above.

**Comments**

    // a single-line comment to the end of the line

**What's missing in v1**

- Strings as a type (only a literal inside `print_str`).
- Pointers, `struct`, 16/32-bit types, `switch`.
- Recursion.
- `+=`/`-=`/... and `++`/`--` - write `i = i + 1;` instead.

**Where to find examples**: `C/DEMOS/COUNTER.MC` (a function,
`DIV`/`MOD`, printing a number), `C/DEMOS/SNAKE.MC` (arrays, mapped
arrays, keyboard, `Clock`), `C/TOOLS/FM.MC` (a file manager,
`exec_child()`, working with the disk directly through `poke`/`peek`),
`C/DEMOS/MUSIC2.MC` (`mod_load()`/`sound_*()`, graphics mode alongside
audio, mapped array over `SoundCard`'s visualization registers).
