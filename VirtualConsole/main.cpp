#include <iostream>
#include <iomanip>
#include <windows.h>

#include "CPU.h"
#include "Memory.h"
#include "Timer.h"
#include "Keyboard.h"
#include "Bus.h"
#include "Assembler.h"

int main()
{
    // Консоль Windows по умолчанию не понимает UTF-8, из-за
    // этого кириллица в выводе превращается в кракозябры
    SetConsoleOutputCP(CP_UTF8);

    // ========================================
    // Создаём компоненты компьютера
    // ========================================

    Memory memory;
    Timer timer;
    Keyboard keyboard;
    Bus bus;
    CPU cpu;
    Assembler assembler;

    // Память занимает нижнюю часть адресного пространства,
    // верхняя часть (0xF000-0xF006) отдана таймеру и клавиатуре
    bus.mapDevice(&memory, 0x0000, 0xEFFF);
    bus.mapDevice(&timer, 0xF000, 0xF004);
    bus.mapDevice(&keyboard, 0xF005, 0xF006);


    // ========================================
    // Ассемблерная программа
    // ========================================

    std::string program = R"(
        JMP main
        JMP irq_handler

    main:

        LDI A, 10
        LDI B, 20

        ADD B

        LDI C, 30
        CMP C

        JZ success

        HLT


    success:

        PUSH A
        LDI A, 0
        POP A

        ; ==== Демонстрация прерываний от таймера ====

        PUSH A          ; сохранить A=30, дальше A используется как scratch

        LDI A, 0
        STA 0x0100      ; irqCount = 0

        LDI A, 100
        STA 0xF002      ; таймер: compare LOW = 100
        LDI A, 0
        STA 0xF003      ; таймер: compare HIGH = 0
        LDI A, 1
        STA 0xF004      ; таймер: включить прерывания

        EI

        PUSH B
        PUSH C

        LDI A, 100
        LDI B, 5
        LDI C, 0

    delay:

        SUB B
        CMP C
        JNZ delay

        POP C
        POP B

        DI

        POP A           ; восстановить исходный A=30

        CALL setD

        HLT


    setD:

        LDI D, 123
        RET


    irq_handler:

        PUSH A
        PUSH B

        LDI A, 1
        STA 0xF004      ; подтвердить прерывание, таймер остаётся включён

        LDA 0x0100
        LDI B, 1
        ADD B
        STA 0x0100      ; irqCount++

        POP B
        POP A

        RETI
    )";


    // ========================================
    // Компилируем программу
    // ========================================

    std::vector<uint8_t> machineCode;

    try
    {
        machineCode = assembler.assemble(program);
    }
    catch (const std::exception& error)
    {
        std::cout << "Assembler error:\n";
        std::cout << error.what() << "\n";

        return 1;
    }


    // ========================================
    // Загружаем программу в память
    // ========================================

    for (size_t i = 0; i < machineCode.size(); i++)
    {
        bus.write(
            static_cast<uint16_t>(i),
            machineCode[i]
        );
    }


    // ========================================
    // Подключаем шину к CPU
    // ========================================

    cpu.connectBus(&bus);

    cpu.reset();

    cpu.running = true;


    // ========================================
    // Запускаем процессор
    // ========================================

    while (cpu.running)
    {
        cpu.step();
    }


    // ========================================
    // Результат
    // ========================================

    std::cout << "\n";
    std::cout << "Virtual Console\n";
    std::cout << "====================\n";

    std::cout << "A = "
        << (int)cpu.A
        << "\n";

    std::cout << "B = "
        << (int)cpu.B
        << "\n";

    std::cout << "C = "
        << (int)cpu.C
        << "\n";

    std::cout << "D = "
        << (int)cpu.D
        << "\n";

    std::cout << "PC = "
        << cpu.PC
        << "\n";

    std::cout << "SP = "
        << cpu.SP
        << "\n";

    std::cout << "FLAGS = "
        << (int)cpu.FLAGS
        << "\n";

    uint16_t timerValue =
        bus.read(0xF000) |
        (bus.read(0xF001) << 8);

    std::cout << "TIMER = "
        << timerValue
        << "\n";

    std::cout << "CYCLES = "
        << cpu.cycles
        << "\n";

    std::cout << "IRQ_COUNT = "
        << (int)bus.read(0x0100)
        << "\n";


    // ========================================
    // Показываем машинный код
    // ========================================

    std::cout << "\nMachine code:\n";

    for (uint8_t byte : machineCode)
    {
        std::cout
            << std::hex
            << std::setw(2)
            << std::setfill('0')
            << (int)byte
            << " ";
    }

    std::cout << std::dec << "\n";

    std::cout.flush();


    // ========================================
    // Интерактивное демо: клавиатура
    // ========================================

    // Таймер остался включён после первого демо (его состояние не
    // сбрасывается между прогонами) - выключаем, иначе он будет
    // продолжать генерировать прерывания и мешать клавиатуре
    bus.write(0xF004, 0);

    std::string keyboardProgram = R"(
        JMP main
        JMP irq_handler

    main:

        LDI A, 1
        STA 0xF006      ; включить прерывания клавиатуры

        LDI A, 0
        STA 0x0102      ; keyCount = 0
        STA 0x0103      ; quit = 0

        LDI D, 0        ; D - константа "0" для сравнений

        EI

    wait:

        LDA 0x0103
        CMP D
        JZ wait

        DI
        HLT


    irq_handler:

        PUSH A
        PUSH B

        LDI A, 1
        STA 0xF006      ; подтвердить прерывание

        LDA 0xF005
        STA 0x0104      ; lastKey = код клавиши

        LDA 0x0102
        LDI B, 1
        ADD B
        STA 0x0102      ; keyCount++

        LDA 0x0104
        LDI B, 27       ; ESC
        CMP B
        JNZ irq_done

        LDI A, 1
        STA 0x0103      ; quit = 1

    irq_done:

        POP B
        POP A

        RETI
    )";

    std::vector<uint8_t> keyboardCode;

    try
    {
        keyboardCode = assembler.assemble(keyboardProgram);
    }
    catch (const std::exception& error)
    {
        std::cout << "Assembler error:\n";
        std::cout << error.what() << "\n";

        return 1;
    }

    for (size_t i = 0; i < keyboardCode.size(); i++)
    {
        bus.write(
            static_cast<uint16_t>(i),
            keyboardCode[i]
        );
    }

    cpu.reset();
    cpu.running = true;

    std::cout << "\nНажимайте клавиши, ESC - выход...\n";
    std::cout.flush();

    while (cpu.running)
    {
        cpu.step();
    }

    std::cout << "\n";
    std::cout << "keyCount = "
        << (int)bus.read(0x0102)
        << "\n";

    std::cout << "lastKey = "
        << (int)bus.read(0x0104)
        << "\n";

    return 0;
}