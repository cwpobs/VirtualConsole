#include <iostream>
#include <iomanip>

#include "CPU.h"
#include "Memory.h"
#include "Assembler.h"

int main()
{
    // ========================================
    // Создаём компоненты компьютера
    // ========================================

    Memory memory;
    CPU cpu;
    Assembler assembler;


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
        memory.write(
            static_cast<uint16_t>(i),
            machineCode[i]
        );
    }


    // ========================================
    // Подключаем память к CPU
    // ========================================

    cpu.connectMemory(&memory);

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