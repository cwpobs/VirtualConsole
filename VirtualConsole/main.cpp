#include <iostream>
#include <fstream>
#include <sstream>
#include <windows.h>

#include "CPU.h"
#include "Memory.h"
#include "Timer.h"
#include "Keyboard.h"
#include "TextVRAM.h"
#include "TextAttr.h"
#include "DebugPort.h"
#include "Disk.h"
#include "VideoCard.h"
#include "Clock.h"
#include "PngLoader.h"
#include "MapLoader.h"
#include "SoundCard.h"
#include "ModLoader.h"
#include "Gpu3D.h"
#include "Bus.h"
#include "Assembler.h"

int main()
{
    // Консоль Windows по умолчанию не понимает UTF-8, из-за
    // этого кириллица в выводе превращается в кракозябры
    SetConsoleOutputCP(CP_UTF8);

    // Кодовая страница ВВОДА - отдельная настройка от вывода.
    // Keyboard::tick() читает байты через _getch(), а тот переводит
    // нажатия по текущей ANSI-кодировке консоли ДО того, как байт
    // попадёт в программу. Выставляем CP866 - ту же страницу, что и
    // TextVRAM использует для отображения, - иначе кириллица на
    // вводе превращается в "?" ещё до Keyboard.
    SetConsoleCP(866);

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
    TextAttr attr;
    Bus bus;
    CPU cpu;
    DebugPort debugPort(&cpu);
    Disk diskC("C", &bus);
    Disk diskD("D", &bus);
    VideoCard videoCard(&keyboard);
    Clock clock;
    PngLoader pngLoader(&videoCard, &diskC);
    MapLoader mapLoader(&videoCard, &diskC);
    SoundCard soundCard;
    ModLoader modLoader(&soundCard, &diskC);
    Gpu3D gpu3D(&videoCard);
    Assembler assembler;

    // 4 МБ RAM с адреса 0, MMIO - далеко наверху (с 0xF0000000),
    // чтобы RAM можно было расширять в будущем, не трогая MMIO.
    // Диапазоны больше не пересекаются, поэтому порядок регистрации
    // устройств на шине не важен
    bus.mapDevice(&memory, 0x00000000, 0x003FFFFF);
    bus.mapDevice(&timer, 0xF0000000, 0xF0000004);
    bus.mapDevice(&keyboard, 0xF0000005, 0xF0000006);
    bus.mapDevice(&vram, 0xF0000007, 0xF00007D8);      // сетка + SCROLL + CLEAR
    bus.mapDevice(&debugPort, 0xF00007D9, 0xF00007E5); // PC/SP/HL/FLAGS (только чтение)
    bus.mapDevice(&diskC, 0xF00007E6, 0xF00007F8);     // диск C (папка "C")
    bus.mapDevice(&diskD, 0xF00007F9, 0xF000080B);     // диск D (папка "D")
    bus.mapDevice(&attr, 0xF000080C, 0xF0000FDD);      // цвет (fg/bg) + SCROLL + CLEAR
    bus.mapDevice(&videoCard, 0xF0000FDE, 0xF0000FFB); // видеокарта 320x240 + 16 спрайтов + тайлы/скролл
    bus.mapDevice(&clock, 0xF0000FFC, 0xF0000FFD);     // часы реального времени (мс, std::chrono)
    bus.mapDevice(&pngLoader, 0xF0000FFE, 0xF0001011); // загрузчик PNG (спрайты и тайлы, stb_image)
    bus.mapDevice(&mapLoader, 0xF0001012, 0xF000101F); // загрузчик текстовой карты тайлов
    bus.mapDevice(&modLoader, 0xF0001020, 0xF0001041); // загрузчик .mod-файлов
    bus.mapDevice(&soundCard, 0xF0001042, 0xF0001044); // звуковая карта (PLAY/STOP/VOLUME)
    bus.mapDevice(&gpu3D, 0xF0001045, 0xF0001065);     // 3D-ускоритель (вершины/треугольники/PRESENT)


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
            static_cast<uint32_t>(i),
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
        vram.render(&attr);

        const uint32_t vramBase = 0xF0000007;

        if (cpu.HL >= vramBase && cpu.HL < vramBase + TextVRAM::SIZE)
        {
            uint32_t offset = cpu.HL - vramBase;

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
    uint8_t lastDoneReady = 0;

    while (cpu.running)
    {
        cpu.step();

        uint8_t currentKeyCount = bus.read(0x00010000);
        uint8_t currentBannerReady = bus.read(0x00010002);
        uint8_t currentDoneReady = bus.read(0x00010003);

        if (currentKeyCount != lastKeyCount ||
            currentBannerReady != lastBannerReady ||
            currentDoneReady != lastDoneReady)
        {
            lastKeyCount = currentKeyCount;
            lastBannerReady = currentBannerReady;
            lastDoneReady = currentDoneReady;

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

    std::cout << "keyCount = " << (int)bus.read(0x00010000) << "\n";
    std::cout << "lastKey = " << (int)bus.read(0x00010001) << "\n";

    return 0;
}
