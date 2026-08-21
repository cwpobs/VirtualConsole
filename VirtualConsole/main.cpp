#include <iostream>
#include <fstream>
#include <sstream>
#include <windows.h>

#include "CPU.h"
#include "Memory.h"
#include "Timer.h"
#include "Keyboard.h"
#include "TextVRAM.h"
#include "Bus.h"
#include "Assembler.h"

int main()
{
    // Консоль Windows по умолчанию не понимает UTF-8, из-за
    // этого кириллица в выводе превращается в кракозябры
    SetConsoleOutputCP(CP_UTF8);

    // Включаем поддержку ANSI-последовательностей (нужно для очистки
    // экрана при живой отрисовке VRAM)
    HANDLE consoleOut = GetStdHandle(STD_OUTPUT_HANDLE);
    DWORD consoleMode = 0;
    GetConsoleMode(consoleOut, &consoleMode);
    SetConsoleMode(consoleOut, consoleMode | ENABLE_VIRTUAL_TERMINAL_PROCESSING);

    // ========================================
    // Создаём компоненты компьютера
    // ========================================

    Memory memory;
    Timer timer;
    Keyboard keyboard;
    TextVRAM vram;
    Bus bus;
    CPU cpu;
    Assembler assembler;

    // Память занимает нижнюю часть адресного пространства,
    // верхняя часть (0xF000-0xF006) отдана таймеру и клавиатуре,
    // 0x8000-0x87CF - текстовая видеопамять (80x25 символов),
    // 0x87D0 - её регистр SCROLL.
    // VRAM регистрируется до Memory: диапазон VRAM физически лежит
    // внутри диапазона Memory, а Bus отдаёт адрес первому подходящему
    // по порядку регистрации устройству
    bus.mapDevice(&vram, 0x8000, 0x87D0);
    bus.mapDevice(&memory, 0x0000, 0xEFFF);
    bus.mapDevice(&timer, 0xF000, 0xF004);
    bus.mapDevice(&keyboard, 0xF005, 0xF006);


    // ========================================
    // Загружаем стартовую программу из файла
    // ========================================

    std::ifstream bootFile("boot.asm");

    if (!bootFile)
    {
        std::cout << "Не удаётся открыть boot.asm "
            << "(запусти exe из папки, где лежит этот файл)\n";

        return 1;
    }

    std::stringstream bootStream;
    bootStream << bootFile.rdbuf();

    std::string program = bootStream.str();


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
    // Подключаем шину к CPU и запускаем
    // ========================================

    cpu.connectBus(&bus);

    cpu.reset();

    cpu.running = true;

    // Очищаем экран один раз (убрать мусор от шелла) и прячем курсор -
    // дальше render() каждый раз перезаписывает все 2000 ячеек целиком
    // (включая пробелы), поэтому повторная очистка не нужна и только
    // вызывает мерцание
    std::cout << "\x1b[2J\x1b[?25l";
    std::cout.flush();

    // Отрисовать экран и поставить настоящий курсор консоли в позицию,
    // соответствующую cpu.HL (в границах видеопамяти)
    auto redraw = [&]()
    {
        // Прячем курсор перед перерисовкой - иначе он на мгновение
        // виден "прыгающим" в начало экрана перед каждым кадром
        std::cout << "\x1b[?25l\x1b[H";
        vram.render();

        int offset = cpu.HL - 0x8000;

        if (offset >= 0 && offset < TextVRAM::SIZE)
        {
            int row = offset / TextVRAM::WIDTH;
            int col = offset % TextVRAM::WIDTH;

            std::cout << "\x1b[" << (row + 1) << ";" << (col + 1) << "H";
        }

        std::cout << "\x1b[?25h";
        std::cout.flush();
    };

    redraw();

    uint8_t lastKeyCount = 0;
    uint8_t lastBannerReady = 0;

    while (cpu.running)
    {
        cpu.step();

        uint8_t currentKeyCount = bus.read(0x0900);
        uint8_t currentBannerReady = bus.read(0x0904);

        if (currentKeyCount != lastKeyCount ||
            currentBannerReady != lastBannerReady)
        {
            lastKeyCount = currentKeyCount;
            lastBannerReady = currentBannerReady;

            redraw();
        }
    }

    // На всякий случай убеждаемся, что курсор терминала остался
    // видимым после выхода из программы
    std::cout << "\x1b[?25h";


    // ========================================
    // Отладочный дамп (хост-диагностика, не часть VM)
    // ========================================

    std::cout << "\n";
    std::cout << "Virtual Console - debug\n";
    std::cout << "====================\n";

    std::cout << "A = " << (int)cpu.A << "\n";
    std::cout << "B = " << (int)cpu.B << "\n";
    std::cout << "C = " << (int)cpu.C << "\n";
    std::cout << "D = " << (int)cpu.D << "\n";
    std::cout << "PC = " << cpu.PC << "\n";
    std::cout << "SP = " << cpu.SP << "\n";
    std::cout << "HL = " << cpu.HL << "\n";
    std::cout << "FLAGS = " << (int)cpu.FLAGS << "\n";
    std::cout << "CYCLES = " << cpu.cycles << "\n";

    std::cout << "keyCount = " << (int)bus.read(0x0900) << "\n";
    std::cout << "lastKey = " << (int)bus.read(0x0902) << "\n";

    return 0;
}
