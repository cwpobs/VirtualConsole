#include <iostream>
#include <iomanip>

#include "CPU.h"
#include "Memory.h"
#include "Timer.h"
#include "Bus.h"
#include "Assembler.h"

int main()
{
    // ========================================
    // Создаём компоненты компьютера
    // ========================================

    Memory memory;
    Timer timer;
    Bus bus;
    CPU cpu;
    Assembler assembler;

    // Память занимает нижнюю часть адресного пространства,
    // верхняя часть (0xF000-0xF001) отдана таймеру
    bus.mapDevice(&memory, 0x0000, 0xEFFF);
    bus.mapDevice(&timer, 0xF000, 0xF001);


    // ========================================
    // Ассемблерная программа
    // ========================================

    std::string program = R"(
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

    std::cout << "\n";


    return 0;
}