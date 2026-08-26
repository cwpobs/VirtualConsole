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
| ConsoleLayer | `0xF0001042` | 1 B | visibility of the text layer over VideoCard |
| PngLoader | `0xF0000FFE-0xF0001011` | 20 B | PNG loading (sprites/tiles) |
| MapLoader | `0xF0001012-0xF000101F` | 14 B | text tile-map loading |
| ModLoader | `0xF0001020-0xF0001041` | 34 B | `.mod` music loading (ProTracker) |
| SoundCard | `0xF0001066-0xF000106E` | 9 B | playback (PLAY/STOP/VOLUME) + visualization (per-channel volume/ROW/ORDER_POS) |
| Mouse | `0xF0001075-0xF000107A` | 6 B | relative mouse movement (sign+magnitude), buttons, capture |
| MatrixLoader | `0xF000108D-0xF00010A3` | 23 B | generic number-matrix loading (level maps etc.) with cell read-back |
| Gpu3D | `0xF0001100-0xF00011FF` | 256 B | 3D accelerator + lighting + 16/32-bit math coprocessor (vertices/triangles/cubes/PRESENT) |
| Phys3D | `0xF0001200-0xF00012FF` | 256 B | physics accelerator: gravity, AABB collision, infinite ground plane |
| KeyState | `0xF0001300` | 1 B | which arrow keys are held down right now |

The CPU has no clock frequency as such — it's a software interpreter
(`CPU::step()`), not real electronic circuitry, so "speed" depends
entirely on the host machine and isn't guaranteed. As a rough
reference point: during development, headless tests of this same
project measured interpreter throughput around ~6 million `step()`
calls/sec on the dev machine — this isn't a spec, just an observation
useful for sizing your own tests.

By default the screen and keyboard are not a Windows console window
at all, but the VM's own graphical window, the **video console**
(`VideoConsole`): a CP866 8x16 bitmap font baked into the code (no
font files on disk), and the very same window that `VideoCard` draws
into (see its section below) — text and graphics share one screen
instead of two separate windows. Selected by the `console` setting in
`config.txt` (`video` by default, `text` — the legacy fallback: a
plain Windows console window with ANSI output and `_getch()` input,
CP866 in/out, see `main.cpp`/`VmConfig.cpp`); in text mode `VideoCard`
has no screen of its own at all — graphics are unavailable there.


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
| 0xF0001042 | ConsoleLayer (text-layer visibility over VideoCard) |
| 0xF0001043 | ModLoaderDiskSelect (explicit disk choice for ModLoader - see "ModLoader") |
| 0xF0001044 - 0xF0001065 | unused gap (old SoundCard/Gpu3D locations - Gpu3D moved to make room for the Light3D/MathUnit merge, see below) |
| 0xF0001066 - 0xF0001074 | SoundCard (PLAY/STOP/PAUSE/RESUME, VOLUME, visualization, pattern-cell query PATTERN_*) |
| 0xF0001075 - 0xF000107A | Mouse (relative movement sign+magnitude, buttons, capture) |
| 0xF000107B - 0xF000108C | unused gap (old MathUnit/Light3D locations - folded into Gpu3D, see below) |
| 0xF000108D - 0xF00010A3 | MatrixLoader (generic number-matrix loading with cell read-back) |
| 0xF0001100 - 0xF00011FF | Gpu3D (3D accelerator + lighting + 16/32-bit math coprocessor - vertices/triangles/cubes/PRESENT; 256 B reserved, ~97 used) |
| 0xF0001200 - 0xF00012FF | Phys3D (physics accelerator: gravity, AABB collision, infinite ground plane; 256 B reserved, ~34 used) |
| 0xF0001300 | KeyState (which arrow keys are held down right now, 1 B) |

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
| 12 | COMMAND (write) | `1`=LIST_FIRST, `2`=LIST_NEXT, `3`=OPEN_READ, `4`=READ_BYTE, `5`=OPEN_WRITE, `6`=WRITE_BYTE, `7`=CLOSE, `8`=LOAD, `9`=DELETE, `10`=LOAD_SHELL, `11`=CHDIR, `12`=CHDIR_UP, `13`=LOAD_RAW, `14`=BUILD, `15`-`18`=LOAD_CHILD (levels 2-5), `19`=MKDIR |
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

`DELETE` (`9`) deletes the file `NAME` (`std::filesystem::remove`) -
also happily removes an EMPTY directory (the same call handles both;
a non-empty directory is simply refused, no recursive delete exists).
`STATUS=0` on success, `STATUS=2` if the file/directory didn't exist,
wasn't empty, or couldn't be deleted. Ready-made usage examples - the
`del` terminal command, and `C/TOOLS/FM.MC`'s `F8` (with a Y/N confirm
dialog first - see `request_delete()`).

`MKDIR` (`19`) creates a new, empty directory `NAME` in the current
folder (`std::filesystem::create_directory`). `STATUS=0` on success,
`STATUS=2` if a file/directory with that name already exists or the
name is invalid. Unlike the other commands here, there's no `mkdir`
terminal command in `SHELL.ASM` (yet) - the only ready-made usage
example is `C/TOOLS/FM.MC`'s `F7` (prompts for a name in a small input
box, then sends `MKDIR` - see `request_mkdir()`).

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
the patched bytes into RAM. If `NAME.RUN` isn't found in the CURRENT
folder, it falls back to two more places before giving up with
`STATUS=2` (unlike `LOAD`/`LOAD_RAW`, which only ever look in the
current folder):

1. **Wherever the currently running top-level program was itself
   loaded from** (`Disk::lastExecDir` - the folder counterpart of
   `lastExecDisk`, updated at the same two moments: `LOAD`/`LOAD_RAW`
   into the main sandbox, see `PngLoader`/`MapLoader`/`ModLoader` above
   for the disk half of this same idea). A shared utility launched via
   `exec_child()` (see `C/TOOLS/VIEW.MC`, launched from `C/TOOLS/FM.MC`'s
   `F3`) naturally lives right next to the program that launches it -
   this fallback finds it there with zero extra setup: build it once,
   in the SAME folder as the calling program's own source, and it's
   found regardless of where that program's `currentDir` has since
   wandered off to (`FM.MC`'s own `currentDir` tracks whichever folder
   the user is currently browsing, which is almost never where `FM.MC`
   itself lives).
2. The disk's ROOT folder, as a last resort, for a utility that isn't
   naturally paired with one specific calling program.

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

## Command-line arguments

DOS-style: typing a space after the program name, followed by more
text, passes that text to the launched program as an argument -

    exec view.mc readme.txt
    view readme.txt          ; same thing, after "build view.mc" once

Works for both `exec NAME` and bare autorun (`NAME` alone, see
`LOAD_RAW` above) - `SHELL.ASM` splits the typed line at the FIRST
space after the program name (`find_name_and_arg_len`); everything
before it is the file name (still capped at 12 bytes - too long and the
whole line is silently ignored, same as an unrecognized command),
everything after it is the argument, handed to the program through a
fixed low-memory channel:

    0x00010005              CMD_ARGS_LEN   (1 byte - argument length, 0 = none)
    0x00010006-0x00010015   CMD_ARGS_TEXT  (16 bytes - raw argument text)

This is the same kind of fixed "interface" address as `lastKey`
(`0x00010001`, see "Interrupts") - reserved by convention, safely clear
of code growth, since `main.cpp`/other programs can't see assembler
labels. Unlike `lastKey`, it isn't read by `main.cpp` - it's read by
whatever program the shell just launched. `SHELL.ASM` always sets it
before `CALL 0x00002000` (`copy_args_to_fixed`, called from
`cmd_exec_run` - the shared tail of both `cmd_exec` and `cmd_autorun`),
including setting it to length 0 when no argument was typed - the same
reasoning as zeroing `lastKey`: otherwise a program would see a STALE
argument left over from whatever ran before it.

A program launched via `exec_child()` (see "Running a child program:
exec_child()" below) gets an argument the same way, but the CALLING
program fills the channel itself, directly, before calling
`exec_child()` - `shell_exec_child` does NOT touch it (same precedent
as `EXEC_CHILD_DISK`, `0x0000000F`, which it also never clears). A
program that doesn't care about arguments simply never reads
`CMD_ARGS_LEN` - a stale value from someone else's previous run is
harmless if nobody looks at it.

From Mini-C, both are already declared for you - `CMD_ARGS_LEN`,
`cmdArgs[16]`, `EXEC_CHILD_DISK` - see "Built-in device register
constants (prelude)" below. Ready-made example: `C/TOOLS/FM.MC`'s `F3`
(`view_selected_file()`) launches `C/TOOLS/VIEW.MC` with the selected
file's name as its argument.


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

**Transparent background (video console only, see "VideoConsole"
below)**: high-nibble value `8` (`TRANSPARENT_BG`) doesn't mean a dark
gray background - it means "don't draw a background at all" - the
`VideoCard` layer (or whatever was already on screen under that cell)
stays visible, only the character glyph itself is drawn in its color.
No program or tool in this project uses background values `8-15` as
an actual color (background is always `0`/`1`/`7` everywhere), so
value `8` was safely repurposed for this special meaning - as a
CHARACTER color (low nibble) `8` still works as plain dark gray, only
the high nibble carries the special meaning. This rule doesn't apply
in the legacy text console (`console=text`) - there's no `VideoCard`
layer to reveal, so background `8` renders as an ordinary dark-gray
ANSI color. Example - `C/DEMOS/SNOW3D.MC` (`place_snowflake()`):
`set_color(col, row, fg, BG_TRANSPARENT)` draws a "snowflake" without
a black box around it, over the graphics.

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

## VideoConsole

The single graphical window for the whole process (Win32 + OpenGL/WGL,
its own thread, doesn't block the CPU loop - same principle as
`VideoCard` below). Not a bus device - no registers/MMIO, programs
work exactly as if there were no video console at all (they write to
`Text VRAM`/`TextAttr`/`VideoCard` as usual). Enabled by default
(`console=video` in `config.txt`); in the legacy text mode
(`console=text`) it's replaced by a plain Windows console window with
ANSI output instead - see "Devices - summary" at the top of this
document.

Two layers of one picture, not two windows:

- **Text** - an 80x25 grid, each cell drawn with a CP866 8x16 bitmap
  font baked into the code (no font files on disk). Window size =
  640x400 times a scale factor (`video_scale` in `config.txt`, default
  2 → a 1280x800 window) - an integer scale, so the glyph stays crisp
  with no smoothing.
- **`VideoCard` graphics** - the background: if `VideoCard` is active
  (between `MODE_ON`/`MODE_OFF`, see its section below), its 320x240
  (4:3) frame is fitted into the 640x400 (8:5) canvas via
  nearest-neighbor scaling, preserving aspect ratio and centered -
  black bars on the sides (~53px at the base scale), since the aspect
  ratios differ. `VideoCard`/`Gpu3D`'s native resolution is unchanged
  by this - it's baked into the 3D projection and into existing
  demos/games alike.

Text-layer transparency rules (see also "ConsoleLayer" and
"TRANSPARENT_BG" in the "TextAttr" section above) - wherever the text
is transparent, the `VideoCard` layer (or whatever was already drawn)
shows through:

- a cell `(space, default attribute 0x07)` - "untouched" after
  `CLEAR`/loading - isn't drawn at all, fully transparent;
- a cell with background `TRANSPARENT_BG` (`8`, see "TextAttr" above)
  - only the character itself is drawn in its color, the background
    is left alone - this is the mechanism for HUDs/effects over
    graphics (example - the "snowflakes" in `C/DEMOS/SNOW3D.MC`, see
    "ConsoleLayer" below).

Keyboard input - the same window catches both `WM_CHAR` (regular
characters, Enter/Backspace/Tab/Esc/Ctrl+letter) and
`WM_KEYDOWN`/`WM_SYSKEYDOWN` (arrows/Home/End/PgUp/PgDn/Delete/F1-F10/
Alt+F1/Alt+F2) - the latter never produce `WM_CHAR` at all, so without
separate handling they'd never reach the program. Keys are translated
into the same DOS scan codes the real console returns via `_getch()`
(`KEYBOARD_DATA`), including the two-byte sequence (a leading byte `0`
for F-keys / `0xE0` for the rest, then the code itself) - a program
reading `KEYBOARD_DATA` can't tell where the key actually came from.

## ConsoleLayer

A single toggle bit - whether the video console's text layer is
visible over `VideoCard`'s graphics. Writing `0` hides it, any other
value shows it; reading returns the current state (0/1). Visible by
default (right after the VM starts).

| Offset | Register | Description |
|----------|---------|----------|
| 0 | CONSOLE_VISIBLE (read/write) | 0 = hidden, 1 (or any nonzero) = visible |

Address: `0xF0001042` (see "Built-in device register constants
(prelude)" in the "Mini-C" section - it already declares the
`CONSOLE_VISIBLE` constant for you).

Two independent sources write to it:

- **`VideoCard`** (see its section below) - `MODE_ON` automatically
  hides the console (but only on the off→on transition - a repeated
  `MODE_ON` during an already-running session doesn't undo what the
  program turned on itself), `MODE_OFF` always brings it back, so a
  graphical program doesn't leave the screen without a console after
  it exits.
- **The program itself** - "combined mode": turn the console back on
  while graphics are already active, and print text (`print_char`/
  `set_color`/`clear_screen`/`poke()` already write to `Text VRAM`/
  `TextAttr` at any time regardless - `CONSOLE_VISIBLE` only decides
  whether what's already there gets shown).

Example - `C/DEMOS/SNOW3D.MC`: `MODE_ON` hides the console
automatically, the demo immediately turns it back on
(`poke(CONSOLE_VISIBLE, 1)`) and keeps printing colorful "snowflakes"
(with `TRANSPARENT_BG`, see "TextAttr" above) over the scrolling tile
map/sprite/spinning 3D cube - a live example of text and graphics at
the same time in one window.


---

## VideoCard

A 320x240 bitmap video mode, RGB (3 bytes per pixel). Unlike
`Text VRAM`/`TextAttr`, the framebuffer is NOT addressed byte-by-byte
over the bus (320*240*3 = 230400 bytes - writing them one at a time
from the CPU would be impractically slow). Instead there's a compact
command protocol (registers + a `COMMAND` trigger), like `Disk`: the
whole framebuffer lives inside the device on the C++ side.

The device has no window/thread/OpenGL context of its own - the only
screen for the whole process is owned by `VideoConsole` (see its
section above), and `VideoCard` is just another layer in its
composition: `MODE_ON`/`MODE_OFF` merely set an "active" flag (and
also toggle `ConsoleLayer`, see its section above) - `VideoConsole`
fits the ready frame (320x240) into its own canvas on every redraw
whenever that flag is set. The heavy composition work still doesn't
happen inside the device's `tick()` (`VideoCard` doesn't override
`tick()` at all) - `tick()` is called on EVERY bus access (see
`CPU::busRead`/`busWrite`), and doing anything expensive there would
repeat the old `Keyboard` bug (see "Keyboard" above), only much worse.
In the legacy text console mode (`console=text`) `VideoCard` has no
screen at all - graphics are unavailable there.

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

- **1 (MODE_ON)** - sets the "active" flag - `VideoConsole` starts
  fitting the 320x240 frame into its own canvas on every redraw (see
  its section above). Automatically hides the console's text layer via
  `ConsoleLayer` (only on the off→on transition - see "ConsoleLayer"
  above). Doesn't block the calling program.
- **2 (MODE_OFF)** - clears the "active" flag and brings the console's
  text layer back (`ConsoleLayer`, unconditionally). The in-memory
  framebuffer isn't cleared. An explicit `MODE_OFF` before the program
  exits is recommended, so the console isn't left hidden.
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
| 9 | PATTERN_ROW_SELECT (write) | row to query in the CURRENTLY playing pattern, 0-63 |
| 10 | PATTERN_CHANNEL_SELECT (write) | channel to query, 0-3 |
| 11 | PATTERN_NOTE (read-only) | note index at (row,channel), 0-35, `255` = no note |
| 12 | PATTERN_SAMPLE (read-only) | sample number at that cell, 0-31 (`0` = none) |
| 13 | PATTERN_EFFECT (read-only) | effect number at that cell, 0-15 |
| 14 | PATTERN_PARAM (read-only) | effect param at that cell, 0-255 |

Addresses: `0xF0001066` (COMMAND) - `0xF0001074` (PATTERN_PARAM). Note the
gap at the old location, `0xF0001042`-`0xF0001044`: this block used to
sit right there, directly before `Gpu3D`, but got too small once the
visualization registers below were added, and growing it in place
would have meant shifting `Gpu3D` and rewriting every hardcoded
address in `CUBE3D.ASM`. Moving the whole block into fresh, unused
space right after `Gpu3D` avoided that entirely - addresses on this
bus were never required to be contiguous. Of that gap, `0xF0001042`
has since been claimed by `ConsoleLayer`, and `0xF0001043` by
`ModLoaderDiskSelect` (see "ModLoader", DISK_SELECT) - only
`0xF0001044` is still free.

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

### Pattern-cell query registers (PATTERN_*)

Unlike `CHANNEL*_VOLUME`/`ROW`/`ORDER_POS` above, these six registers
are NOT mirrors refreshed once per tick by the audio thread - they're
computed fresh on every read: writing `PATTERN_ROW_SELECT` (0-63) and
`PATTERN_CHANNEL_SELECT` (0-3) selects a cell in the CURRENTLY playing
pattern (`song.orderTable[ORDER_POS]`), then `PATTERN_NOTE`/
`PATTERN_SAMPLE`/`PATTERN_EFFECT`/`PATTERN_PARAM` read its fields.
`PATTERN_NOTE` isn't the raw period - it's a ready-made index 0-35 into
the same 36-note table as `PERIOD_TABLE` (below), found by an exact
match against the cell's period; `255` means either the cell has no
note at all (period=0) or the period didn't match any standard value
(an unusual finetune, etc.). Any invalid query (no song loaded,
`ORDER_POS`/pattern number out of range, `PATTERN_ROW_SELECT >= 64`, or
`PATTERN_CHANNEL_SELECT >= 4`) returns an "empty" cell (`NOTE=255`,
everything else `0`) rather than an error - the same style every
read-only register on this bus already follows.

Added for a live note/sample/effect view - `C/TOOLS/PLAYER.MC`'s
"blocks racing by" visualizer, in the spirit of classic trackers (see
"Playlist (PLAY.LST)" below, which covers that whole file, subsection
"Blocks racing by"). The query only reaches into the CURRENTLY playing
pattern - a row scrolled past its start/end (0-63) does not pull in the
neighboring pattern from the order table; the caller decides what to
show in that case (a blank row, etc.).

`getQueryCell()` (`SoundCard.cpp`) locks `songMutex` for the duration
of the read - `song` (samples/patterns/order table) is replaced wholesale
by `loadSong()` on every new `LOAD` through `ModLoader`, and that's the
same object `getQueryCell()` reads from.

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
`MapLoader`: the `.mod` format itself isn't tied to the 8.3 convention
the other loaders follow - a name longer than 12 bytes is no problem
for `ModLoader`. `ModLoader` doesn't go through `Disk` (it reads the
file itself), so the 12-byte limit elsewhere is just those devices' own
choice, not a general rule of the bus. The actual `.mod` shipped in
this repo, `C/DEMOS/SPACE_~1.MOD`, is nonetheless named in DOS 8.3
style with `~1` - the way a long `space_debris.mod` would get
truncated under real DOS - because that same name also lives on disk
"C" (see `Disk`) and has to fit the 12-byte `NAME` there, or
`FM.MC`/`SHELL.ASM` couldn't list/copy/rename it properly.

| Offset | Register | Description |
|----------|---------|----------|
| 0-31 | NAME0-31 | name of the `.mod` file (see DISK_SELECT below for which disk) |
| 32 | COMMAND (write = trigger) | 1 = LOAD |
| 33 | STATUS (read-only) | 0=ok, 1=file not found, 2=unsupported format (not M.K./4 channels/31 samples), 3=corrupted/too-short file |

Addresses: `0xF0001020` (NAME0) - `0xF0001041` (STATUS).

### DISK_SELECT - explicit disk choice (`0xF0001043`)

A separate one-byte device, `ModLoaderDiskSelect` (not part of
`ModLoader`'s own contiguous range - see the "old SoundCard spot"
sidebar below for why it has to be physically separate): `0` = resolve
as before, via `Disk::lastExecDisk` (the disk the currently running
program was actually launched from - the default value, no behavior
change for code that never writes this register), `1` = force disk C,
`2` = force disk D. Added for the playlist, where the same running
program (`C/TOOLS/PLAYER.MC`) needs to load tracks from either disk
within a SINGLE run - `lastExecDisk` alone can't do that, it's fixed for
the whole run of the program. Written BEFORE `COMMAND=LOAD` and stays in
effect until the next `LOAD` overwrites it - see
`C/TOOLS/PLAYER.MC::load_mod_from_playlist()` for a full working
example, and the "Playlist (PLAY.LST)" section below.

Command **1 (LOAD)** reads the file `NAME`, parses it (header, 31
sample descriptors, order table, patterns, sample PCM data) and, in
one call, puts the result into `SoundCard` (fully replaces the
current song, resets the sequencer to the start - you need to
explicitly send `SoundCard.PLAY` afterward to hear it, `LOAD` doesn't
start playback itself).

Example - load `SPACE_~1.MOD` and play it:

    LDI A, 83   ; 'S'
    STA 0xF0001020
    LDI A, 80   ; 'P'
    STA 0xF0001021
    ; ... the rest of the file name's letters in NAME2-11, unused ones = 0 ...

    LDI A, 1
    STA 0xF0001040      ; COMMAND = LOAD

    LDA 0xF0001041       ; STATUS
    LDI B, 0
    CMP B
    JNZ mod_error

    LDI A, 1
    STA 0xF0001066      ; SoundCard COMMAND = PLAY

A full working example - `C/DEMOS/MUSIC.ASM` (`cd demos`, then
`exec music.asm`), song - `C/DEMOS/SPACE_~1.MOD`.


---

## Gpu3D

A 3D accelerator, lighting, and a math coprocessor - ONE device. It used
to be three (`Gpu3D`/`Light3D`/`MathUnit`), each with barely any address
room to grow; live testing showed that split apart to be a bad idea (no
spare registers, and juggling three small devices for what is really one
"3D + math" subsystem), so they were merged - see `misty-zooming-bee.md`.
All the math (model/camera matrices, perspective projection, z-buffered
rasterization, general 16/32-bit arithmetic and trigonometry) lives on
the C++ side - the processor is nowhere near capable of it (it doesn't
even have proper multiplication without byte overflow). The assembly
side only sees commands at the level of "here's a vertex", "draw a
triangle", "draw a cube", "compute A+B", "show the frame" - the whole 3D
scene accumulates in `Gpu3D`'s OWN internal buffer (its own 320x240
color buffer + its own z-buffer + a mask of "touched" pixels) and is
handed to `VideoCard` all at once with a `PRESENT` command (see
"Hardware tiles and scrolling" above for the full layer order - 3D is
drawn OVER the tiles, but UNDER the sprites).

The address range is deliberately generous - 256 bytes, `0xF0001100`-
`0xF00011FF` - even though under half of it is wired to a real register
today. The whole point is room to grow (more light sources, a texture
upload protocol richer than the current fixed 32x32 squares) without
another renumbering; unused offsets just read 0 and ignore writes.

Color is per vertex (Gouraud shading, like on the PS1/N64); the
rasterizer linearly interpolates color (or, for a textured triangle,
the sampled texel - see "Textures" below) and depth across a triangle's
three vertices. The vertex color submitted through `VR`/`VG`/`VB` is
the triangle's *base* color, used when `VTEXTURE = 0` (untextured, the
default) - if a normal is set (`VNX`/`VNY`/`VNZ`) before
`SUBMIT_VERTEX`, the actual color stored for that vertex is the base
color modulated by the light (see "Lighting" below); a vertex submitted
with no normal set (the default, all zeros) gets no directional
shading, only whatever the ambient level contributes.

| Offset | Register | Description |
|----------|---------|----------|
| 0-1 | VX_LOW/HIGH | vertex X, signed 16-bit, model units |
| 2-3 | VY_LOW/HIGH | vertex Y |
| 4-5 | VZ_LOW/HIGH | vertex Z |
| 6 | VR | vertex/cube color, R (0-255) - ignored when textured |
| 7 | VG | vertex/cube color, G - ignored when textured |
| 8 | VB | vertex/cube color, B - ignored when textured |
| 9-11 | VNX/VNY/VNZ | normal of the *next* vertex submitted (see "Lighting" below) |
| 12 | VU | texture U of the *next* vertex (0-255 = 0.0-1.0) |
| 13 | VV | texture V of the *next* vertex |
| 14 | VTEXTURE | texture slot of the *next* vertex (0 = no texture, else 1-8 - see "Textures" below) |
| 15 | COMMAND (write = trigger) | 1=SUBMIT_VERTEX, 2=DRAW_TRIANGLE, 3=CLEAR, 4=PRESENT, 5=DRAW_CUBE |
| 16 | STATUS (read-only) | 0=ok, 1=DRAW_TRIANGLE called without 3 accumulated vertices |
| 17-18 | CUBE_SIZE_LOW/HIGH | half edge length of the next `DRAW_CUBE`, signed 16-bit |
| 19-24 | OBJ_X/Y/Z_LOW/HIGH | object position in the world, signed 16-bit |
| 25-30 | OBJ_YAW/PITCH/ROLL_LOW/HIGH | object rotation, degrees (signed 16-bit) |
| 31-36 | CAM_X/Y/Z_LOW/HIGH | camera position in the world |
| 37-40 | CAM_YAW/PITCH_LOW/HIGH | camera rotation (no roll) |
| 41-43 | LIGHT_DIR_X/Y/Z | light direction, world space |
| 44-46 | LIGHT_R/G/B | light color/intensity (0-255 per channel) |
| 47 | AMBIENT | background light level (0-255) |
| 48-55 | *(reserved)* | free |
| 56-63 | see "Math (16-bit)" below | |
| 64-77 | see "Math (32-bit)" below | |
| 78-96 | see "Textures" below | |

`OBJ_*`/`CAM_*` take effect immediately on write, with no command
(like sprite position/map scroll) - rotating an object or moving the
camera every frame should be cheap (a few `STA`s, no extra command
byte).

All nine direction/normal registers (`VNX`/`VNY`/`VNZ`/`LIGHT_DIR_*`)
use the same fixed-point encoding: a signed byte, `/100.0` (100 = 1.0,
`156` = -1.0, i.e. `256 - 100`). One byte is plenty of range for a unit
vector - no low/high pair needed here, unlike `Gpu3D`'s world
coordinates which need the full 16 bits. `VNX`/`VNY`/`VNZ` should be set
right before each `SUBMIT_VERTEX` (like `VR`/`VG`/`VB`) -
`Gpu3D::submitVertex()` snapshots them into that vertex at the moment
`SUBMIT_VERTEX` runs.

Addresses: `0xF0001100` (VX_LOW) - `0xF00011FF` (end of reserved range).

### Commands

- **1 (SUBMIT_VERTEX)** - adds the current `VX/VY/VZ/VR/VG/VB/VNX/VNY/
  VNZ` to an internal triangle-vertex accumulator. Designed for exactly
  3 vertices - the calling code must send `SUBMIT_VERTEX` three times
  before every `DRAW_TRIANGLE` (like `WRITE_PIXEL` for `VideoCard`'s
  sprites/tiles, just without auto-incrementing an index - here it's
  always exactly 3 vertices per triangle).
- **2 (DRAW_TRIANGLE)** - applies the model matrix (`OBJ_*` - the
  object's translation and rotation) and the camera matrix (`CAM_*`)
  to the 3 accumulated vertices, projects them into screen coordinates
  (320x240, a fixed vertical FOV of ~70°), and rasterizes the triangle
  into `Gpu3D`'s OWN internal buffer - barycentric rasterization,
  Gouraud color interpolation, a per-pixel z-buffer test (only a nearer
  pixel overwrites a farther one). A triangle with even one vertex
  behind the camera (or closer than the minimum distance) is discarded
  entirely - there's no proper plane clipping in v1 (a simplification:
  not an issue for convex objects like a cube at typical demo
  distances). Doesn't touch `VideoCard` directly - only its own
  internal buffer.

  Before rasterizing - backface culling: if a vertex has a normal set
  (`VNX/VNY/VNZ` nonzero - `normalLenSq > 0`) AND the dot product of the
  world-space normal with the "camera to vertex" vector is positive
  (the face points away from the camera), the whole triangle is
  discarded. Geometry with NO normal set (old demos that wrote
  triangles by hand before `VNX/VNY/VNZ` existed, e.g.
  `CUBE3D.ASM`/`SNOW3D.MC`) is never culled - backward compatibility.
  `DRAW_CUBE` (below) always sets axis-aligned normals, so its geometry
  is fully subject to culling. This removes both the z-fighting flicker
  between facing interior faces of adjacent cubes and the "inside of the
  cube" artifact visible when the camera sits right up against a face
  (see also the `COLLISION_SKIN` margin in `Phys3D` below - previously
  the only, insufficient, mitigation for this).
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
- **5 (DRAW_CUBE)** - a hardware fast path for the extremely common
  case of an axis-aligned cube. Instead of the CPU sending 36
  `SUBMIT_VERTEX`s (12 triangles × 3 vertices, ~13 register writes
  each - hundreds of bus transactions per cube), it writes just the
  center (`VX/VY/VZ`), half edge length (`CUBE_SIZE_LOW/HIGH`), and
  base color (`VR/VG/VB`), then triggers `DRAW_CUBE` once. `Gpu3D`
  builds all 8 corners and 12 triangles (with the correct axis-aligned
  normal per face, and a full `(0,0)-(1,1)` UV quad per face) internally
  and rasterizes them through the exact same pipeline as
  `DRAW_TRIANGLE` - same model/camera transform, same lighting, same
  z-buffer. If `VTEXTURE` is non-zero when the command runs, all 6 faces
  get that one texture (see "Textures" below) instead of the
  `VR`/`VG`/`VB` color. Doesn't touch `pendingVertices` at all, so
  it's safe to mix `DRAW_CUBE` and manual `SUBMIT_VERTEX`/
  `DRAW_TRIANGLE` calls within the same frame. Doesn't call `CLEAR`/
  `PRESENT` itself - same convention as `DRAW_TRIANGLE`, the caller
  clears once per frame and presents once per frame, after drawing
  everything. This was added specifically because a floor built out of
  many individually-submitted cubes (`C/DEMOS/CUBEWRLD.MC`) was far too
  slow for interactive use - see `misty-zooming-bee.md`.

### Lighting

One directional light + an ambient level, computed once per vertex
(Gouraud - interpolated across the triangle by the existing rasterizer,
same as color always was): the vertex normal is rotated by the same
object rotation as the vertex position (but not translated), then

    brightness = AMBIENT/255 + (LIGHT_channel/255) * max(0, dot(worldNormal, normalize(LIGHT_DIR)))
    finalColor = clamp(baseColor * brightness, 0, 255)

is applied per color channel. A vertex with a zero normal (the default)
always has `dot(...) = 0`, so it only ever gets the ambient term -
useful for objects that don't care about lighting. `DRAW_CUBE` computes
the correct axis-aligned normal per face itself, so cubes are always lit
correctly without the caller setting `VNX`/`VNY`/`VNZ`.

### Math (16-bit)

| Offset | Register | Description |
|----------|---------|----------|
| 56-57 | MATH_A_LOW/HIGH | operand A, signed 16-bit |
| 58-59 | MATH_B_LOW/HIGH | operand B, signed 16-bit |
| 60 | MATH_COMMAND (write = trigger) | 1=ADD, 2=SUB, 3=MUL, 4=DIV, 5=SIN, 6=COS, 7=SQRT |
| 61 | MATH_STATUS (read-only) | 0=ok, 1=error (divide by zero, or `sqrt` of a negative A) |
| 62-63 | MATH_RESULT_LOW/HIGH (read-only) | result of the last command |

Not tied to 3D specifically - any program needing real 16-bit
arithmetic or trigonometry can use it (the CPU's `MUL`/`DIV` are 8-bit
only, and mini-C's `long` type supports only +/- against a plain `int`,
see "The `long` type" below), the way `CUBEWRLD.MC`'s camera movement
does (see `C/DEV/LIB/GEOM3D.MC`). `SIN`/`COS` treat `A` as an angle in
degrees (same convention as `*_YAW`/`*_PITCH`/`*_ROLL` above) and ignore
`B`; the result is fixed-point `*100` (100 = 1.0), the same scale the
light/normal registers use. `SQRT` uses only `A` and requires `A >= 0`.

Addresses: `0xF0001138` (MATH_A_LOW) - `0xF000113F` (MATH_RESULT_HIGH).

### Math (32-bit)

| Offset | Register | Description |
|----------|---------|----------|
| 64-67 | MATH32_A0-A3 | operand A, signed 32-bit, little-endian (byte 0 = least significant) |
| 68-71 | MATH32_B0-B3 | operand B, signed 32-bit, little-endian |
| 72 | MATH32_COMMAND (write = trigger) | 1=ADD, 2=SUB, 3=MUL, 4=DIV, 5=SQRT |
| 73 | MATH32_STATUS (read-only) | 0=ok, 1=error (divide by zero, or `sqrt` of a negative A) |
| 74-77 | MATH32_RESULT0-3 (read-only) | result of the last command, little-endian |

The wider counterpart to the 16-bit block above, for values that don't
fit in 16 bits (large world coordinates, distances, anything that would
overflow). No `SIN`/`COS` here - angles never need 32-bit range, they
stay on the 16-bit block.

Addresses: `0xF0001140` (MATH32_A0) - `0xF000114D` (MATH32_RESULT3).

### Textures

Texture loading lives inside `Gpu3D` itself rather than a separate
device - by design (see `misty-zooming-bee.md`): `Gpu3D` decodes a PNG
atlas (via `stb_image`, the same library `PngLoader` uses) and cuts out
32x32 regions into its OWN texture memory (`TEXTURE_SLOTS` = 8 slots,
32x32 RGB each - a few tens of KB, trivial). The protocol is
deliberately identical to `PngLoader`'s (see its section above): `LOAD`
decodes the file into a cached RGBA buffer, `EXTRACT` cuts one 32x32
square out of that cache into a numbered slot - one `LOAD` serves many
`EXTRACT`s of the same atlas without re-decoding.

| Offset | Register | Description |
|----------|---------|----------|
| 78-89 | TEX_NAME0-11 | atlas PNG file name, 8.3 format |
| 90-91 | TEX_SRC_X_LOW/HIGH | X of the region to cut, in the atlas |
| 92-93 | TEX_SRC_Y_LOW/HIGH | Y of the region to cut |
| 94 | TEX_SLOT | destination slot, 1-8 |
| 95 | TEX_COMMAND (write = trigger) | 1=LOAD, 2=EXTRACT |
| 96 | TEX_STATUS (read-only) | 0=ok, 1=file not found / nothing loaded yet, 2=region out of bounds, 3=invalid slot |

Addresses: `0xF000114E` (TEX_NAME0) - `0xF0001160` (TEX_STATUS).

Slot `0` is reserved to mean "no texture" - `VTEXTURE` (offset 14,
described above as reserved) is now live: set on the next vertex
submitted (like `VR`/`VG`/`VB`), along with `VU`/`VV` (offsets 12-13,
0-255 = 0.0-1.0 texture coordinates). A textured triangle samples the
slot named by `VTEXTURE` (nearest-neighbor, no filtering - the same
pixel-art aesthetic the rest of the project already uses) at the
per-pixel interpolated `(u, v)`, and the sampled texel REPLACES the
triangle's base color entirely - lighting (ambient + diffuse) still
multiplies on top of it exactly as it does for a plain-colored vertex.
An untextured vertex (`VTEXTURE = 0`, the default) renders exactly as
before - nothing changes for existing demos that never touch these
registers.

`DRAW_CUBE` (see above) also honors `VTEXTURE`: if non-zero when the
command runs, all 6 faces get the SAME texture (one texture per cube,
the same way one base color already applies to the whole cube), each
face UV-mapped as a full `(0,0)-(1,0)-(1,1)-(0,1)` quad. `VR`/`VG`/`VB`
are ignored for a textured cube - the texture fully replaces them.

Working example - `C/DEMOS/CUBEWRLD.MC`: loads `TILES.PNG` once, cuts
two 32x32 tiles into slots 1 and 2, and draws the two floor layers with
`draw_cube_at(..., texSlot)` (see `C/DEV/LIB/GEOM3D.MC`).

### Example

Draw a single triangle (camera at `(0,0,-150)`, the cube/object at the
origin with no rotation - both are the defaults):

    LDI A, 106
    STA 0xF0001123      ; CAM_Z_LOW  (-150 in 16-bit two's complement)
    LDI A, 255
    STA 0xF0001124      ; CAM_Z_HIGH

    LDI A, 3
    STA 0xF000110F      ; COMMAND = CLEAR

    ; vertex 0: (-30,-30,0), red
    LDI A, 226
    STA 0xF0001100      ; VX_LOW
    LDI A, 255
    STA 0xF0001101      ; VX_HIGH
    ; ... similarly VY_LOW/HIGH = -30, VZ_LOW/HIGH = 0 ...
    LDI A, 255
    STA 0xF0001106      ; VR = 255
    LDI A, 0
    STA 0xF0001107      ; VG = 0
    STA 0xF0001108      ; VB = 0
    LDI A, 1
    STA 0xF000110F      ; COMMAND = SUBMIT_VERTEX

    ; ... vertices 1 and 2 the same way ...

    LDI A, 2
    STA 0xF000110F      ; COMMAND = DRAW_TRIANGLE

    LDI A, 4
    STA 0xF000110F      ; COMMAND = PRESENT

A full working example - `C/DEMOS/CUBE3D.ASM` (`cd demos`, then
`exec cube3d.asm`): a spinning colored cube (12 triangles, 2 per
face) with a UI icon on top (a sprite from `SPRITES.PNG`). A much
faster equivalent using the `DRAW_CUBE` hardware primitive plus a
lit, textured-later floor loaded from a level file -
`C/DEMOS/CUBEWRLD.MC` (see `C/DEV/LIB/GEOM3D.MC` for the mini-C
wrapper functions).

## Mouse

Relative mouse movement (not absolute screen position - there's no
register for where the cursor is, only how far it moved) - built for
FPS-style "mouse looks around" camera control, not for pointing at
things on screen.

| Offset | Register | Description |
|----------|---------|----------|
| 0 | DELTA_X_SIGN (read-only) | 0 = right, 1 = left |
| 1 | DELTA_X_MAG (read-only) | accumulated |X movement| since last read (0-127); reading resets it to 0 |
| 2 | DELTA_Y_SIGN (read-only) | 0 = up, 1 = down |
| 3 | DELTA_Y_MAG (read-only) | accumulated |Y movement| since last read; reading resets it to 0 |
| 4 | BUTTONS (read-only) | bit 0 = left button, bit 1 = right button |
| 5 | CONTROL | bit 0 = capture (1 = hide the cursor and lock it to the window center, feeding `DELTA_*` from the movement that would otherwise have moved the cursor off-window; 0 = normal system cursor, no deltas accumulate) |

Movement is reported as sign+magnitude, not a signed byte - this
plays well with mini-C's 8-bit `int` (unsigned, wraparound
arithmetic): the caller reads `*_SIGN` first, then `*_MAG` (magnitude
read clears the accumulator, so read the sign *before* the magnitude,
not after), and adds or subtracts the magnitude depending on the sign
instead of having to interpret a raw two's-complement byte.

Addresses: `0xF0001075` (DELTA_X_SIGN) - `0xF000107A` (CONTROL).

## MatrixLoader

A generalization of `MapLoader` (see above) for "any map that can be
described as a matrix of numbers" - a level layout, a collision grid,
anything - rather than specifically a `VideoCard` tile map.
`MapLoader` itself is untouched (`TILEDEMO.ASM`/`TSCROLL.MC`/
`SNOW3D.MC` depend on its exact behavior); `MatrixLoader` is a
separate device with two differences:

- values are the full byte range 0-255 (not 0-127 - a cell's value
  isn't necessarily a tile index here);
- the matrix is queryable cell-by-cell from the CPU after loading -
  `MapLoader` only ever pushes its result into `VideoCard` and can't
  be read back at all.

| Offset | Register | Description |
|----------|---------|----------|
| 0-11 | NAME0-11 | file name, 8.3 format (same convention as `Disk`/`PngLoader`/`MapLoader`) |
| 12 | COMMAND (write = trigger) | 1=LOAD |
| 13 | STATUS (read-only) | 0=ok, 1=file not found, 2=parse error |
| 14-15 | WIDTH_LOW/HIGH (read-only) | matrix width, set by LOAD |
| 16-17 | HEIGHT_LOW/HIGH (read-only) | matrix height, set by LOAD |
| 18-19 | CELL_X_LOW/HIGH | X of the cell to query next |
| 20-21 | CELL_Y_LOW/HIGH | Y of the cell to query next |
| 22 | CELL_VALUE (read-only) | value at `(CELL_X, CELL_Y)`, computed on read; 0 if out of bounds |

File format is identical to `MapLoader`'s: each line is one row,
decimal numbers separated by whitespace, every row the same length
(a rectangular matrix), trailing blank lines ignored - see "MapLoader"
above for the exact parsing rules. `C/DEMOS/LEVEL.TXT` is an example
(an 8x8 grid, values 0-2 - see `C/DEMOS/CUBEWRLD.MC`, which treats
the value as a stack height in cubes).

Addresses: `0xF000108D` (NAME0) - `0xF00010A3` (CELL_VALUE).

## KeyState

Whether an arrow key is held down RIGHT NOW - deliberately separate from
`Keyboard` (see above), which is a queue built for typing (one byte per
keypress) and turns out to be a poor fit for continuous movement: while
a key is held, Windows resends `WM_KEYDOWN` repeatedly (key-repeat), and
a program consuming only one queue byte per frame falls behind - worse,
every other byte consumed during a burst is the two-byte extended-key
*prefix* (see `Keyboard`'s section above), which matches no key code at
all. The result is the jerky, stuttering movement `C/DEMOS/CUBEWRLD.MC`
had before this device existed (see `misty-zooming-bee.md`) - a queue
can't represent "held", only "happened".

`KeyState` is a single-byte bitmask, updated by `VideoConsole` directly
on `WM_KEYDOWN`/`WM_KEYUP` (not through any queue) - at any instant it
reflects exactly which arrows are currently down, with no accumulation
and no loss. `Keyboard` is untouched and still used for everything it
already did (FM/EDIT navigation, one-shot actions like Ctrl+Q) - reading
`KeyState` for movement and `KEYBOARD_DATA` for a quit keystroke in the
same loop is the intended pattern, see `C/DEMOS/CUBEWRLD.MC`.

| Bit | Key |
|---|---|
| 0 | UP |
| 1 | DOWN |
| 2 | LEFT |
| 3 | RIGHT |
| 4-7 | reserved |

Address: `0xF0001300` (1 byte, read-only). Prelude constants (see
"Built-in device register constants" below): `KEYSTATE`, `KEYSTATE_UP`,
`KEYSTATE_DOWN`, `KEYSTATE_LEFT`, `KEYSTATE_RIGHT` - e.g.
`if (peek(KEYSTATE) & KEYSTATE_UP) { ... }`.

## Phys3D

A physics accelerator - gravity, AABB collision volumes, and an
infinite ground plane ("horizon") - deliberately a SEPARATE device from
`Gpu3D`, not paired with it (see `misty-zooming-bee.md`; pairing them is
explicitly left as a possible future task). Same reasoning as every
other accelerator in this system: the CPU can't do this math, the
device can, at whatever precision it needs internally.

The key design choice, learned from `Gpu3D`'s own performance history:
static level geometry (the cubes) is described to the device ONCE, at
level-load time (`DEFINE_BOX`, one call per solid cube - like a texture
or a map, "define it and forget it") rather than resent every frame.
The only thing that crosses the bus every frame is a single `STEP`
command - "move the player by (dx,dy,dz), resolve collisions" - the
device does the O(number of boxes) work internally in C++.

| Offset | Register | Description |
|---|---|---|
| 0-1 | GROUND_Y_LOW/HIGH | Y of the "horizon" - the infinite ground plane, signed 16-bit |
| 2-3 | GRAVITY_LOW/HIGH | fall acceleration, units/frame², signed 16-bit |
| 4 | BOX_SLOT | static collider slot index, 0-127 |
| 5-10 | BOX_X/Y/Z_LOW/HIGH | box center, signed 16-bit |
| 11-13 | BOX_HALF_X/Y/Z | box half-extent per axis, 0-255 |
| 14 | BOX_COMMAND (write = trigger) | 1=DEFINE (create/update the box at BOX_SLOT), 2=CLEAR_ALL |
| 15 | BOX_STATUS (read-only) | 0=ok, 1=invalid slot |
| 16 | PLAYER_RADIUS | player collision radius, 0-255 (player is a SPHERE, not an AABB - see below); offsets 17-18 unused |
| 19-24 | PLAYER_X/Y/Z_LOW/HIGH | player position - write directly to spawn/teleport (no collision check, like `Gpu3D`'s `OBJ_X`); read back after `STEP` for the resolved position |
| 25-30 | MOVE_DX/DY/DZ_LOW/HIGH | desired movement this frame - set before `STEP` |
| 31 | GROUNDED (read-only) | 1 = resting on the ground plane or a box |
| 32 | STEP_COMMAND (write = trigger) | 1=STEP |
| 33 | STEP_STATUS (read-only) | 0=ok |

Up to 128 static boxes (`MAX_BOXES`) - enough for a fully-solid
`C/DEMOS/LEVEL.TXT`-sized grid (64 cells × 2 stacked layers).

Addresses: `0xF0001200` (GROUND_Y_LOW) - `0xF0001221` (STEP_STATUS), out
of a 256-byte reserved range (`0xF0001200`-`0xF00012FF`) - same
generous-headroom convention as `Gpu3D`.

### STEP - the algorithm

1. An internal (not a register) `velocityY` accumulates `GRAVITY` every
   step, reset to 0 when the player was resting (`GROUNDED`) at the
   start of the step.
2. The player's sphere moves by the FULL vector at once - `(MOVE_DX,
   MOVE_DY + velocityY, MOVE_DZ)` - not one axis at a time. An earlier
   version resolved X, then Z, then Y separately (the "move, test, push
   out" approach many simple 3D platformers use) - moving diagonally
   into a box's corner could still tunnel the camera partway into the
   geometry for a frame, since each axis pass only sees a 1D overlap,
   not the true point of contact.
3. For every active box: find the closest point on the box to the
   sphere's center (per-axis clamp), and if the distance from that
   point to the center is less than `PLAYER_RADIUS`, push the center
   out along that direction (the true direction of penetration, corner
   or face alike) by `radius - distance` - **plus a small skin margin**
   (a couple of units) so the sphere never comes to rest touching a
   face exactly - without it, the camera can end up close enough to a
   face that turning reveals the cube's inside (a safety margin in case
   something isn't already discarded by backface culling in `Gpu3D`'s
   rasterizer, see its section above - the same class of artifact
   z-fighting between adjacent cubes was, worked around there with a
   similar small gap). A push that's mostly "up" (see the sign
   convention above) counts as landing - sets `GROUNDED=1` and zeroes
   `velocityY`, whether the box was landed on from above or the ground
   plane below.

   Step 3 repeats several times in a row (`COLLISION_RESOLVE_PASSES`,
   currently 3) per `STEP`, rather than running once: a single pass only
   pushes the sphere out of one box at a time, so in a corner formed by
   two walls the first pass can push it out of the first box straight
   into the second - later passes settle the position outside both.
4. Separately, the same skin-margined check against the `GROUND_Y`
   plane.
5. Write back the resolved `PLAYER_X/Y/Z` and `GROUNDED`.

Full 3D collision, not just "walls" - a box can be landed on from above
(the player falls onto it) exactly the same way as the ground plane; a
"block sideways movement only" primitive would have been a special
case of this, not the other way around. Boxes themselves stay AABB
(defined by three half-extents) - only the PLAYER is a sphere, which is
what makes the closest-point trick above a simple, well-known
sphere-vs-AABB test.

Working example - `C/DEMOS/CUBEWRLD.MC` (see `C/DEV/LIB/PHYS3D.MC` for
the mini-C wrapper functions `phys_define_box()`/`phys_step()`/etc.):
defines one box per wall block at load time (the floor itself needs no
box - the `GROUND_Y` plane already covers it everywhere), then each
frame sends one `STEP` with the desired horizontal movement and copies
the resolved position into `Gpu3D`'s `CAM_X/Y/Z` - the camera IS the
player.

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

The main type is `int`, unsigned 8-bit (like the CPU registers).
Overflow silently wraps around, as it does everywhere in this
assembler. There's also `long`, a 16-bit scalar with a deliberately
narrow set of supported operations (see "The `long` type" below), and
`string`, a two-dimensional, fixed-shape "array of strings" (see "The
`string` type" below) for cases like the playlist, where a plain
`int arr[N]` runs into its 255-element index ceiling.

Variables are **global only** - there's no such thing as a real local
variable with a stack frame (the CPU has no "SP+offset" addressing).
`int x;` written inside `main()`/any function or at the top level of
the file is, in both cases, the same named memory cell (`x: DB 0` in
the generated ASM) - the only difference is that inside a function you
can assign it an initial value right away: `int x = 5;`.

Fixed-size arrays - top level only:

    int arr[16];

The index is normally 8-bit (0-255) - `arr[i]` works for both reads
and writes. Implemented with the same tricks as `cmdbuf`/`NAME` in
`SHELL.ASM`: `LDHL` to the array's base address + `INCHL` in a loop the
needed number of times (a separate routine, `__mc_hladd`, which the
compiler appends to the end of the program by itself if arrays were
used at all). Indexing by a `long` variable instead (see "The `long`
type" below) lifts this to 65535 elements - `arr[16]` still only
reserves 16 bytes, so the array size itself has never been limited to
255, only how far a plain `int` index could reach into it.

### The `long` type

    long i;
    i = 0;
    while (i < 2000) {
        bigArr[i] = something;
        i = i + 1;
    }

`long` is a 16-bit unsigned scalar (0-65535), added specifically so
array indices and loop counters can go past the 255-element ceiling of
a plain `int` index, without giving the CPU's 8-bit ALU any real
16-bit arithmetic to do. Under the hood a `long NAME;` reserves two
bytes - `NAME` (low) and a hidden `NAME__hi` (high, a separate label -
the assembler has no "label+1" operand arithmetic) - the same split
`ADC`/`SBC` carry-chain trick already used by `__mc_screen_offset` for
`y*80+x` (see "Mapped arrays" above).

On purpose, only a narrow set of forms is supported - anything else is
a compile error (`Мини-C: строка N: 'NAME' - long (16 бит), нельзя
использовать напрямую как обычное значение...`) rather than a silently
truncated or wrong result:

- `long NAME;` - declaration (global only, like `int`; no `long`
  function parameters or return values in v1).
- `NAME = <intExpr>;` - assigns an `int`-range expression, zero-extended
  (high byte set to 0).
- `NAME = NAME + <intExpr>;` / `NAME = NAME - <intExpr>;` - the only
  supported arithmetic: increment/decrement by a plain `int` value,
  carried between the two bytes via `ADC`/`SBC`. Any other combination
  (`long + long`, `*`, `/`, `%`, bitwise ops, `long` on the right of
  `+`/`-`) is a compile error.
- Comparisons in `if`/`while` - `NAME < intExpr`, and `NAME < otherLong`
  (`<=`, `>`, `>=`, `==`, `!=` too) - compares high bytes first, low
  bytes only on a tie, same two-step chain a human would do by hand.
- `arr[NAME]` - using a bare `long` variable as an array index, see
  "Mapped arrays" above. Only a bare identifier works as a `long`
  index - a compound expression like `arr[i + 1]` where `i` is `long`
  is a compile error, not silent truncation.

Using a `long` variable directly as an ordinary 8-bit value (as a
plain expression, function argument, `print_char`, etc.) is also a
compile error - there's no implicit narrowing, since silently dropping
the high byte would be exactly the kind of bug this type exists to
prevent.

No demo/tool in this project currently uses `long` for its own data
(`EDIT.MC`'s in-memory buffer, for example, still uses the older
one-array-per-line scheme - see "Example: VIEW.MC / DISKIO.MC" below)
- it exists so that future code needing a bigger array (a longer text
buffer, a bigger level, etc.) doesn't have to invent its own ad-hoc
16-bit workaround.

### The `string` type

    string playlist[16][36];
    playlist[2][0] = 65;
    ch = playlist[2][0];
    print_string(4, 5, playlist, 2);

`string NAME[COUNT][WIDTH];` - COUNT strings of WIDTH bytes each
(plain `int` bytes, always its own storage - unlike `int arr[N] =
address;`, strings have no mapped variant, there's nothing for them to
window into in MMIO). Solves the same problem `long` already solves for
one-dimensional arrays - just for TWO-dimensional indexing. A plain
`arr[i]` computes its address as `base + i` via `__mc_hladd`, which
hard-zeroes the high byte of the resulting offset (see above, `long` as
an index) - so `i` can never exceed 255: not a soft cap on array size,
a hard limit on what `__mc_hladd` is even capable of computing. Because
of this, an "array of strings" (say, up to 16 playlist paths at 36
bytes each - `16*36=576`) wouldn't fit in any single `int arr[N]` at
all - only as a scatter of N parallel arrays of the same shape plus an
`if` cascade picking the right one by a runtime index (the existing
example of exactly this trick, for SCREEN rows - `row0[32]`...
`row13[32]` in `C/DEV/SRC/SNAKE.MC`, `set_cell(x,y,ch)`).

`string` instead computes the offset `row*WIDTH+col` with the same
trick `__mc_screen_offset` already uses for `y*80+x` (see "Screen
built-in functions" below) - NOT an 8-bit `MUL` (would overflow at
modest COUNT/WIDTH already), but an `ADD`/`ADC` loop accumulating a
real 16-bit byte pair, then one `ADDHL` at the end (internal helper
`__mc_str_offset`, a parameterized clone of `__mc_screen_offset` - the
WIDTH comes from the declaration of the SPECIFIC string array being
indexed, rather than being hardcoded like the screen's 80).
`playlist[i][j]` - both read and write - works for any `i` (up to 255)
and `j` (up to 255) within the declared COUNT/WIDTH; going past the
declared bounds isn't checked at runtime, same as ordinary arrays.

`print_string(x, y, NAME, index)` - a built-in function, prints the
string `NAME[index]` starting at `(x, y)`, stopping at the first zero
byte or after WIDTH characters, whichever comes first - a runtime
analog of `print_str`, but for content computed at runtime (read from a
file, typed by the user, etc.) rather than a string literal known at
compile time. `NAME` is resolved at codegen time (like `str_copy()`'s
first argument), `index` is an ordinary runtime `int` expression.

Deliberately NOT added: concatenation, string comparison, a mapped
variant (`= address`) - none of it is needed by the one existing
consumer (`C/TOOLS/PLAYER.MC`'s playlist - see "Playlist (PLAY.LST)"
below), and would have been speculative completeness without real use.
Working example - `C/TOOLS/PLAYER.MC`: `playlist[16][36]`, filled by
`load_playlist()` (reads `PLAY.LST` via `DISKIO.MC`), shown by
`run_playlist_menu()`/`render_playlist()` via `print_string()`.

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

## Built-in device register constants (prelude)

Before your own source is compiled, the compiler silently prepends a
fixed block of `const`/mapped-array declarations for the registers most
graphics/tile programs need - `Keyboard`, `Clock`, `VideoCard`
(background, hardware sprites, tile scroll), `ConsoleLayer`,
`PngLoader`, `MapLoader`, `Mouse`, `MatrixLoader`, `KeyState` (see their sections
above for what each register does). You don't declare these yourself -
they're just already there, named with a device prefix so registers
that share a name across devices (`COMMAND`, `STATUS`) don't collide:

    KEYBOARD_DATA, KEYBOARD_CONTROL
    CLOCK_LOW, CLOCK_HIGH
    VIDEOCARD_X_LOW .. VIDEOCARD_STATUS                 (background)
    VIDEOCARD_SPRITE_INDEX .. VIDEOCARD_SPRITE_STATUS   (hardware sprites)
    VIDEOCARD_SCROLL_X_LOW .. VIDEOCARD_SCROLL_Y_HIGH   (tile scroll)
    CONSOLE_VISIBLE
    PNGLOADER_NAME0, PNGLOADER_SRC_X_LOW .. PNGLOADER_TILE_INDEX
    MAPLOADER_NAME0, MAPLOADER_COMMAND, MAPLOADER_STATUS
    MOUSE_DELTA_X_SIGN .. MOUSE_CONTROL
    MATRIXLOADER_NAME0 .. MATRIXLOADER_CELL_VALUE
    KEYSTATE, KEYSTATE_UP, KEYSTATE_DOWN, KEYSTATE_LEFT, KEYSTATE_RIGHT
    EXEC_CHILD_DISK
    CMD_ARGS_LEN

`Gpu3D` (which also covers lighting and the 16/32-bit math coprocessor,
see its section above) and `Phys3D` are the exceptions - their registers
are NOT in the prelude, they're declared by hand as plain `const`s in
the `C/DEV/LIB/GEOM3D.MC` and `C/DEV/LIB/PHYS3D.MC` libraries
(`#include "GEOM3D.MC"` / `#include "PHYS3D.MC"` - see "#include" below,
including multiple `#include` lines in the same file) - the addresses
are stable, and adding them to the prelude the same way as the rest
would be easy, it just hasn't been done, to keep the prelude focused on
devices almost every program touches rather than the 3D/physics-specific
ones.

Three ready-made mapped arrays over the `NAME0-11` buffers come
prepended alongside them - `pngLoaderName`/`mapLoaderName`/
`matrixLoaderName` (`int ...[12] = ...;`), meant to be used directly
with `str_copy()` (see below) instead of writing a device's file name
byte by byte. Another, `cmdArgs[16]`, is a
mapped array over `CMD_ARGS_TEXT` (see "Command-line arguments" in the
"Disk" section above) - the argument text after the program's own name
on the command line, or whatever a parent program placed there before
calling `exec_child()`.

If your own program happens to declare a `const`/array under the same
name, yours simply wins - the compiler has no duplicate-declaration
check (see "const" above, it's a plain "last one assigned" map), and
your own declaration compiles AFTER the prelude. Line numbers in your
own error messages are unaffected either way: the prelude is lexed as
its own chunk with its own line counter restarting at 1, entirely
independent of your file's - the same mechanism `#include` (see below)
uses for library files.

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
    print_string(x, y, arr, i);   // prints the STRING arr[i] (see "The `string` type") - runtime analog of print_str
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

To also pass the child an argument (see "Command-line arguments" in
the "Disk" section above), fill `cmdArgs`/`CMD_ARGS_LEN` yourself
before calling `exec_child()` - `shell_exec_child` doesn't touch that
channel, only your own code does:

    cmdArgs[0] = 84; cmdArgs[1] = 88; cmdArgs[2] = 84;   // "TXT" - or str_copy(cmdArgs, "...")
    poke(CMD_ARGS_LEN, 3);
    poke(EXEC_CHILD_DISK, diskId);
    exec_child();

Ready-made example - `C/TOOLS/FM.MC`'s `F3` (`view_selected_file()`):
puts `VIEW.RUN` in `NAME` (the program to launch) and the SELECTED
file's name in `cmdArgs` (the argument) - two different strings at the
same time, which is exactly why this needs its own channel separate
from `NAME`.

## Sound and music: mod_load()/sound_*()

    if (mod_load("SPACE_~1.MOD") != 0) { return 1; }   // STATUS: 0=ok,1=not found,2=bad format,3=corrupted
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

## str_copy() - copying a string literal into a mapped array

    str_copy(pngLoaderName, "TILES.PNG");
    poke(PNGLOADER_COMMAND, 1);          // LOAD - str_copy() doesn't trigger it itself
    if (peek(PNGLOADER_STATUS) != 0) { ... }

Copies a string literal into a mapped array (`int arr[N] = address;`,
see "Mapped arrays" above) at compile time - the same trick `mod_load`
uses (a flat sequence of `LDI A,<byte>; STA <address>` pairs, zero-padded
to fill the rest), generalized to work with ANY mapped array instead of
just `ModLoader`'s fixed `NAME0-31`. Meant for writing a device's file
name in one line instead of one `poke()`/array-element assignment per
character - e.g. filling `PngLoader`'s or `MapLoader`'s `NAME` buffer
through the prelude's `pngLoaderName`/`mapLoaderName` (see "Built-in
device register constants" above) before triggering `LOAD`/`EXTRACT`/
etc. yourself.

Unlike `mod_load`, `str_copy()` does NOT trigger any device command on
its own - it's purely "copy these bytes"; the `poke(..._COMMAND, ...)`
that actually does something with them is a separate, explicit step
(the same buffer might get filled and reused for several different
commands in a row - `LOAD`, then `EXTRACT_TILE` several times, say).
Compile-time errors: the array must be mapped (a plain, non-mapped
array has nowhere sensible to copy device-facing bytes to), and the
string must fit within the array's own declared size (zero-padded if
shorter, a hard compile error if longer - no silent truncation).

## #include - shared library files

    #include "STRLIB.MC"

Pulls in another Mini-C source file at compile time - a library of
`const`s/functions you don't want to retype into every program, kept in
one place. Libraries always live in a FIXED location - disk C, folder
`DEV/LIB` (the real file `C/DEV/LIB/STRLIB.MC` next to the emulator
executable) - regardless of which disk the program actually being
built lives on; `build`'s preprocessing step (`Disk::build()`) always
looks there, never in the current folder or on the other disk.

A `#include` line must be the ONLY thing on its line (surrounding
whitespace is fine) - `build` scans the raw source TEXT for such lines
BEFORE Mini-C's own lexer ever runs (`#` isn't a valid character
anywhere else in the language), reads the named file's full text, and
replaces the `#include` line with a blank one - so line numbers for the
REST of your own file are completely unaffected. Each included
library's text is then lexed as its own independent chunk with its OWN
line counter starting at 1 (the same mechanism the built-in device
prelude above uses) - a syntax error inside a library reports the
correct line INSIDE that library file, not some shifted position in
yours.

A library file is plain Mini-C text - `const`s, `int arr[N] = addr;`,
functions - with no `main()` of its own (it's never compiled standalone,
only spliced into whoever includes it). Deliberate v1 limitations:

- Only the top-level file passed to `build` is scanned for `#include` -
  a library's own text is not itself re-scanned, so a library can't
  include another library (no nested/recursive includes to worry about).
- Works for `.MC` builds only, not `.ASM`.
- A missing/misspelled library file, or a malformed `#include` line
  (missing quotes), fails the whole `build` (`STATUS=2`, same as any
  other build error).
- Re-including the same library twice (or a name that happens to
  collide with something you declared yourself) isn't an error - same
  "last declaration wins" tolerance as everywhere else in the compiler
  (see "const" above) - not an include guard, just harmless by
  construction.
- A library's file name is matched against the raw source TEXT before
  any real Mini-C token exists - it does NOT go through `Disk`'s
  12-byte `NAME` register protocol like ordinary `.MC`/`.RUN` file
  names do, so it isn't restricted to 8.3 naming, though staying short
  is still a reasonable convention.

See `C/DEV/LIB/STRLIB.MC` (a small `print_number3(x, y, value)` helper)
and `C/DEV/SRC/LIBDEMO.MC` (includes it) for a working example.

## What's deliberately missing in v1

- String LITERALS as a runtime value - `print_str`/`mod_load`/
  `str_copy` still only accept them as text compiled into a fixed
  destination, never as a variable. Runtime strings as such DO exist
  (see "The `string` type") - just without comparison or concatenation,
  which the one existing consumer (`PLAYER.MC`'s playlist) never
  needed, so they weren't added speculatively.
- Pointers, `struct`, `switch`, any 16-bit arithmetic beyond what
  `long` supports (see "The `long` type"), no 32-bit type.
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

`C/DEMOS/MUSIC2.MC` plays `SPACE_~1.MOD` (`mod_load()` +
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

## Example: STRLIB.MC / LIBDEMO.MC

`C/DEV/LIB/STRLIB.MC` is a tiny reusable library - one function,
`print_number3(x, y, value)`, printing a 0-255 value as three decimal
digits (the same digit-splitting trick as `COUNTER.MC`/`SNAKE.MC`'s
`show_score`, factored out into something any other program can pull in
instead of retyping it). `C/DEV/SRC/LIBDEMO.MC` is the minimal
`#include` example - `#include "STRLIB.MC"` then a plain call to
`print_number3()`, as if the function had been typed directly into the
file. Build and run:

    build libdemo.mc
    libdemo

## Example: VIEW.MC / DISKIO.MC

`C/DEV/LIB/DISKIO.MC` is a small library of `Disk`-register wrappers
parameterized by `diskId` (0=C, 1=D) - the same `d_cmd`/`d_status`/
`d_data`/`d_set_data` pattern already used directly inside `C/TOOLS/
FM.MC`, factored out for new consumers instead of copy-pasting it again
(`FM.MC` itself keeps its own copies - no need to churn working code).
Besides the file commands (`OPEN_READ`/`READ_BYTE`/`OPEN_WRITE`/
`WRITE_BYTE`/`CLOSE`) there's `diskio_chdir(diskId)`/
`diskio_chdir_up(diskId)` (`CHDIR`/`CHDIR_UP`, see "Disk" above) -
needed by `C/TOOLS/PLAYER.MC`'s playlist, see "Playlist (PLAY.LST)"
below.
`C/TOOLS/VIEW.MC` is a paged text-file viewer built on top of it and
`STRLIB.MC`'s `print_number3()`: it reads its file name from `cmdArgs`
(see "Command-line arguments" in the "Disk" section, and "Built-in
device register constants" above) and which disk to read it from via
`peek(EXEC_CHILD_DISK)`, then re-opens the file and re-counts newlines
from the start on every page flip rather than holding the whole file in
memory (Mini-C arrays can't exceed 255 elements - see "Types and
variables" above - a real text file wouldn't fit). Controls - `Up`/
`Down` - previous/next page (24 lines each, the 25th screen row is a
status line), `Esc` - back to whoever launched it. `C/TOOLS/FM.MC`'s
`F3` (`view_selected_file()`) launches it with the selected file as its
argument. Build and run directly:

    build view.mc
    view readme.txt

`F3` from `FM.MC` just works, with no extra setup, as long as `VIEW.RUN`
is built in the SAME folder as `FM.MC` itself (`C/TOOLS`) - `LOAD_CHILD`'s
origin-folder fallback (see "LOAD_CHILD" in the "Disk" section) finds it
there via `Disk::lastExecDir`, regardless of which folder `FM.MC`'s
panels happen to be browsing when `F3` is pressed - no copying `.RUN`
files around, no fixed "put it at the root" convention to remember.

## Playlist (PLAY.LST)

`C/TOOLS/PLAYER.MC` (see "Sound and music" above) can play not just a
single track named as an argument, but a list: `player` with no
arguments looks next to itself (`C/TOOLS/PLAY.LST`) for a text
playlist file and shows a selectable list (arrows/`Enter`, hints at the
bottom - the same style as `FM.MC`'s `render_status()`).

`PLAY.LST` format - one track per line, `<DISK>/<path from disk root>`:

    C/DEMOS/SPACE_~1.MOD
    D/GAMES/SONG.MOD

`<DISK>` is the letter `C` or `D` (byte `68` = `'D'`, anything else is
treated as `C` - see `load_mod_from_playlist()`); the path after the
first `/` is NOT split into segments or walked one folder at a time via
`CHDIR` at all - it's copied as-is into `ModLoader`'s 32-byte `NAME`
(`std::filesystem::path::operator/`, which is what `ModLoader::load()`
uses to resolve the path on the C++ side, already correctly understands
embedded `/` inside a single string - see `ModLoader.cpp`). The only
thing `PLAYER.MC` itself has to do before loading is make sure the
CHOSEN disk's `currentDir` points at the ROOT (otherwise the path in
the playlist would resolve relative to wherever `player` actually got
launched from, not the root) - just select the disk once via
`MODLOADER_DISK_SELECT` (see "ModLoader" above) and send `CHDIR_UP`
several times in a row (a safe no-op at the root, DOS-style - see
"Disk").

Up to 16 lines, no scrolling (`PLAYLIST_MAX`/`PLAYLIST_WIDTH` in
`PLAYER.MC`) - extra lines are silently ignored, as is the tail of a
line longer than `PLAYLIST_WIDTH` bytes. Stored in `string
playlist[16][36]` (see "The `string` type" above) - this was in fact
the reason `string` got added to the language: 16 parallel `int`
arrays plus an `if` cascade (the older trick, see `SNAKE.MC`) for
arbitrary-length paths would have been considerably more verbose.

`DISKIO.MC` (see "Example: VIEW.MC / DISKIO.MC" below) was extended
with two wrappers for reading `PLAY.LST` itself and resetting
`currentDir` to the root: `diskio_chdir(diskId)` (`CHDIR`, enters the
folder written into `NAME` via `diskio_set_name_char`) and
`diskio_chdir_up(diskId)` (`CHDIR_UP`).

Controls while picking a track: `Up`/`Down` - move through the list,
`Enter` - play the selected track (reuses the same visualizer/playback
loop as single-track mode), `Ctrl+Q` - exit the player entirely.

Controls while a track is playing (see `play_track_loop()` in
`PLAYER.MC`) - `Ctrl+Q` exits the player entirely in EITHER launch mode
(a filename argument or the playlist), `P` - pause/resume. Playlist mode
adds three more: `Esc` - stop and go back to the list (`ACTION_MENU`),
`Left`/`Right` - previous/next track (`ACTION_PREV`/`ACTION_NEXT`)
WITHOUT wrapping at the ends of the list - `play_track_loop()` itself
checks `sel > 0`/`sel < count - 1` BEFORE stopping the track, so an
arrow key on the first/last track silently does nothing instead of
stopping and immediately restarting the same one. In single-track mode
(launched with a filename argument) these three keys aren't active at
all - there's nowhere to go back or switch to, `play_track_loop()` gets
`playlistMode=0`.

Elapsed track time (`elapsedMin`/`elapsedSec` in `PLAYER.MC`, `mm:ss`
format) is shown in a corner of the screen next to `Order`/`Row`. MOD
files don't carry a real duration - the sequencer never precomputes
one, and an honest calculation would be approximate anyway because of
`Fxx` tempo/speed-change effects inside the song itself (see
"SoundCard" above) - so only "how long we've been playing" is shown,
with no total length. It isn't accumulated from `Clock`
(`CLOCK_LOW`/`CLOCK_HIGH`, see "Clock" above - `wait_ms()` already uses
it for per-frame waiting and resets it on every call), but
approximately: 30 iterations of the `wait_ms(33)` loop are counted as
one second. The small drift (30×33ms=990ms, not exactly 1000) doesn't
matter for a corner-of-the-screen stopwatch.

### Blocks racing by - a live pattern view

Below the VU meters (screen rows 13-24, previously unused), `PLAYER.MC`
draws a classic-tracker-style window of 9 rows from the CURRENTLY
playing pattern, across all 4 channels - real notes/samples/effects,
not an abstract animation (see "Pattern-cell query registers
(PATTERN_*)" in the "SoundCard" section above - all the real work lives
there, `PLAYER.MC` just queries and prints). Cell format is
`"C-3 01 A02"` (note, hex sample number, hex effect+param), `"---"` for
an empty cell (no note).

The "current row" cursor is ALWAYS in the same spot on screen (the
middle one, slot 5 of 9) - it's the content around it that moves, not
the cursor: `draw_pattern_view()` (in `PLAYER.MC`) recomputes the
`[ROW-4, ROW+4]` window and re-queries all 36 cells (9 rows × 4
channels) every time `ROW` changes, while `draw_pattern_frame()`
(background/border/current-row highlight) is drawn only once, when the
track starts - the same "don't recolor what hasn't changed" principle
already used throughout the rest of the visualizer. Rows that scroll
past the start/end of the pattern (`ROW-4 < 0` or `ROW+4 > 63`) render
blank - see the query's own limitation, above, of never reaching outside
the current pattern.

Note names (`noteNames[36][4]`, a `string` - see "The `string` type"
above) are filled once at startup (`init_note_names()`), in the same
order as `PERIOD_TABLE` in `SoundCard.cpp`: 3 octaves of 12 semitones
each, classic tracker "letter, sharp-or-dash, octave" format (`"C-1"`,
`"C#1"`, ... `"B-3"`).

## Built-in tools: FM.MC / EDIT.MC / VIEW.MC keybindings

Three ready-made Mini-C programs live in `C/TOOLS` and are meant to be
built once and used from the shell like any other OS tool - `build
fm.mc` / `build edit.mc` / `build view.mc`, then run as `fm` / `edit
NAME` / `view NAME`.

### FM.MC - file manager

A two-panel Norton-Commander-style file manager (see `C/TOOLS/FM.MC`'s
own header comment for the full design rationale - independent
per-panel disk/folder via `sync_disk_to_panel()`, launching other
programs via `exec_child()`, etc.). Each panel browses a disk (C or D)
independently, including both panels on the same physical disk at
different folders.

| Key | Action | Details |
|---|---|---|
| `Tab` | switch the active panel | |
| `Up`/`Down` | move the selection | |
| `Enter` | enter a folder, or run the selected `*.RUN` | via `exec_child()`, "Running a child program" |
| `Backspace` | go up one folder | |
| `F2` | Rename - prompts for a new name, prefilled with the current one | `request_rename()`/`perform_rename()` |
| `F3` | View - opens the selected file in `VIEW.MC` | `view_selected_file()` |
| `F4` | Edit - opens the selected file in `EDIT.MC` (full-screen editor) | `edit_selected_file()` |
| `F5` | Copy the selected file | |
| `F6` | Move (copy + delete the source) | `do_move()` |
| `F7` | MkDir - creates a folder in the active panel's current folder | `request_mkdir()`/`perform_mkdir()` |
| `F8` | Delete the selected file/empty folder, after a Y/N confirmation | `request_delete()` |
| `F9` | New file - creates an empty file in the active panel's current folder and immediately opens it in `EDIT.MC` | `request_newfile()`/`perform_newfile()` |
| `F10` | Build - compiles/assembles the selected `*.MC`/`*.ASM` via the `BUILD` disk command, prints `Build OK`/`Build FAILED: <error>` on the status line | `build_selected_file()`; case-insensitive extension check, matches `Disk::readErrorByte()` |
| `Alt+F1` / `Alt+F2` | switch the left/right panel's disk (C/D) | `select_disk_left()`/`select_disk_right()` |
| `Ctrl+Q` | quit | |

A `..` entry appears at the top of the listing whenever the panel
isn't at the disk root; `Enter` on it goes up a folder, same as
`Backspace` - it can't be deleted/moved/copied/built
(`is_dotdot_selected()`).

### EDIT.MC - full-screen text editor

The whole file is held in memory - one array per line
(`line0[80]..line47[80]`, `MAX_LINES=48`/`MAX_COLS=80`), accessed only
through `get_char(row,col)`/`set_char(row,col,v)`, because Mini-C has
no arrays-of-arrays and a plain `int` array tops out at 255 elements
(see "Types and variables" above - `EDIT.MC` predates the `long` type
and hasn't been rewritten to use it). A file longer than `MAX_LINES`
lines, or with a line longer than `MAX_COLS`, opens **truncated**
(status bar shows `TRUNCATED`) rather than silently losing data -
saving a truncated buffer requires an extra Y/N confirmation, since it
permanently discards whatever didn't fit.

| Key | Action |
|---|---|
| arrows | move the cursor |
| `Home`/`End` | start/end of the current line |
| `PgUp`/`PgDn` | scroll one screen up/down |
| `Enter` | split the line at the cursor |
| `Backspace`/`Delete` | delete a character (merges with the neighboring line at a line boundary) |
| `Ctrl+S` | save |
| `Esc` | quit - with unsaved changes, asks `Y`/`N`/`Esc` (save-and-quit / quit-without-saving / cancel) |

If the named file doesn't already exist, `EDIT.MC` opens a new empty
buffer instead of failing (unlike `VIEW.MC`, which refuses in that
case). Launched from `FM.MC` via `F4`/`F9`, or directly: `exec edit.mc
NAME` / `edit NAME` after building once.

### VIEW.MC - paged text-file viewer

Doesn't hold the file in memory - re-opens it and re-counts newlines
from the start on every page flip instead, since a real text file
wouldn't fit in a 255-element array. Refuses to open a file that
doesn't exist (unlike `EDIT.MC`).

| Key | Action |
|---|---|
| `Up`/`Down` | previous/next page (24 lines each; row 25 is a status line) |
| `Esc` | back to whoever launched it |

Launched from `FM.MC` via `F3`, or directly: `exec view.mc NAME` /
`view NAME` after building once. See "Example: VIEW.MC / DISKIO.MC"
above for the underlying `DISKIO.MC` library it's built on.

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
| `long i;` | a 16-bit scalar (0-65535) - only `=`/`+`/`-` with an `int`, comparisons, and as an array index | "The `long` type" |
| `arr[i]` (`i` is `long`) | array index up to 65535, instead of the usual 255 ceiling | "The `long` type" |

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

**Built-in device register constants**

Already declared for you in every program - `KEYBOARD_*`, `CLOCK_*`,
`VIDEOCARD_*` (background/sprites/scroll), `CONSOLE_VISIBLE`,
`PNGLOADER_*`, `MAPLOADER_*`, `MOUSE_*`, `MATRIXLOADER_*`, `KEYSTATE`/
`KEYSTATE_UP/DOWN/LEFT/RIGHT`, `EXEC_CHILD_DISK`, `CMD_ARGS_LEN`, plus
ready mapped arrays `pngLoaderName`/`mapLoaderName`/`matrixLoaderName`/
`cmdArgs`. `GPU3D_*` (3D + lighting + math coprocessor) and `PHYS_*`
(physics accelerator) are NOT in the prelude - `#include "GEOM3D.MC"`/
`#include "PHYS3D.MC"` instead (see "#include" below). See "Built-in
device register constants (prelude)" above for the full list.

**Screen (Text VRAM/TextAttr)**

| Call | What it does |
|---|---|
| `clear_screen()` | clears both text and color |
| `print_char(x, y, ch)` | character `ch` (0-255, CP866) into cell `(x, y)` |
| `print_str(x, y, "text")` | a string literal starting at `(x, y)`, no wrapping |
| `print_string(x, y, arr, i)` | the string `arr[i]` (see "The `string` type") - runtime analog of `print_str` |
| `set_color(x, y, fg, bg)` | the cell's color, `fg`/`bg` - 0-15 |

**Child programs**

    poke(EXEC_CHILD_DISK, diskId);   // 0=C, 1=D
    exec_child();                    // run *.RUN from NAME on disk diskId, returns after its RET

    cmdArgs[0] = 65; poke(CMD_ARGS_LEN, 1);   // optional: pass an argument (or str_copy(cmdArgs, "..."))

See "Running a child program: exec_child()" above - up to 5 nesting
levels, zeroes `lastKey` before launching, the disk and file name in
`NAME` are prepared by the calling code beforehand; `cmdArgs`/
`CMD_ARGS_LEN` are yours to fill if the child takes an argument (see
"Command-line arguments" in the "Disk" section).

**Sound and music**

| Call | What it does |
|---|---|
| `mod_load("name.mod")` | loads a `.mod` file into `SoundCard`, returns `STATUS` |
| `sound_play()` / `sound_stop()` | start/stop playback |
| `sound_pause()` / `sound_resume()` | pause/resume without resetting position |
| `sound_set_volume(v)` | overall volume, 0-255 |

See "Sound and music: mod_load()/sound_*()" above.

**str_copy()**

    str_copy(arr, "text");   // arr must be a mapped array - int arr[N] = address;

Copies a string literal into a mapped array at compile time, zero-padded
to the array's size, no device command triggered - see "str_copy() -
copying a string literal into a mapped array" above.

**#include**

    #include "NAME.MC"

Pulls in a library file from disk C, `DEV/LIB`, at compile time - see
"#include - shared library files" above.

**Comments**

    // a single-line comment to the end of the line

**What's missing in v1**

- Strings as a type (only as a literal inside `print_str`/`mod_load`/
  `str_copy`, each copying it into a fixed destination at compile time -
  never a runtime value you can pass around).
- Pointers, `struct`, `switch`, any 16-bit arithmetic beyond what
  `long` supports (see "The `long` type"), no 32-bit type.
- Recursion.
- `+=`/`-=`/... and `++`/`--` - write `i = i + 1;` instead.

**Where to find examples**: `C/DEMOS/COUNTER.MC` (a function,
`DIV`/`MOD`, printing a number), `C/DEMOS/SNAKE.MC` (arrays, mapped
arrays, keyboard, `Clock`), `C/TOOLS/FM.MC` (a file manager,
`exec_child()`, working with the disk directly through `poke`/`peek`),
`C/DEMOS/MUSIC2.MC` (`mod_load()`/`sound_*()`, graphics mode alongside
audio, mapped array over `SoundCard`'s visualization registers),
`C/DEV/LIB/STRLIB.MC` + `C/DEV/SRC/LIBDEMO.MC` (`#include`, a reusable
library function), `C/DEV/LIB/DISKIO.MC` + `C/TOOLS/VIEW.MC` (reading a
file with the low-level `Disk` protocol, command-line arguments via
`cmdArgs`, `exec_child()` launched from `C/TOOLS/FM.MC`'s `F3`).
