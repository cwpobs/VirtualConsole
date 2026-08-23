#include <chrono>
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
#include "VideoConsole.h"
#include "VmConfig.h"
#include "ConsoleLayer.h"

int main()
{
    VmConfig config = VmConfig::load("config.txt");

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
    // экрана при живой отрисовке VRAM) - только для текстовой
    // консоли; видеоконсоль в ANSI-вывод вообще ничего не пишет (см.
    // VmConfig, ключ console).
    if (!config.useVideoConsole)
    {
        HANDLE consoleOut = GetStdHandle(STD_OUTPUT_HANDLE);
        DWORD consoleMode = 0;
        GetConsoleMode(consoleOut, &consoleMode);
        SetConsoleMode(consoleOut, consoleMode | ENABLE_VIRTUAL_TERMINAL_PROCESSING);
    }

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
    ConsoleLayer consoleLayer;
    VideoCard videoCard(&consoleLayer);
    Clock clock;
    PngLoader pngLoader(&videoCard, &diskC);
    MapLoader mapLoader(&videoCard, &diskC);
    SoundCard soundCard;
    ModLoader modLoader(&soundCard, &diskC);
    Gpu3D gpu3D(&videoCard);
    Assembler assembler;
    VideoConsole videoConsole(&keyboard, &videoCard, &consoleLayer, config.videoConsoleScale);

    if (config.useVideoConsole)
    {
        videoConsole.start();
    }

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
    bus.mapDevice(&gpu3D, 0xF0001045, 0xF0001065);     // 3D-ускоритель (вершины/треугольники/PRESENT)
    // Старое место SoundCard (см. ниже, блок SoundCard целиком перенесён
    // ПОСЛЕ Gpu3D, чтобы не сдвигать его и не переписывать жёстко
    // зашитые адреса в CUBE3D.ASM) - 0xF0001042 занят под ConsoleLayer,
    // 0xF0001043-0xF0001044 всё ещё не используются.
    bus.mapDevice(&consoleLayer, 0xF0001042, 0xF0001042); // видимость текстового слоя поверх VideoCard (0/1)
    bus.mapDevice(&soundCard, 0xF0001066, 0xF000106E); // звуковая карта (PLAY/STOP/VOLUME + визуализация: громкость каналов/ROW/ORDER_POS)


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
    // вызывает мерцание. Актуально только для ANSI-пути - видеоконсоль
    // рисует в собственное окно и ничего в OS-консоль не пишет.
    if (!config.useVideoConsole)
    {
        std::cout << "\x1b[2J\x1b[?25l";
        std::cout.flush();
    }

    const uint32_t vramBase = 0xF0000007;

    // Отрисовать экран и поставить курсор в позицию, соответствующую
    // cpu.HL (в границах видеопамяти) - на текстовой консоли настоящим
    // курсором терминала, на видеоконсоли - нарисованным мигающим
    // блоком (см. VideoConsole::rasterize)
    auto redraw = [&]()
    {
        bool cursorInBounds = cpu.HL >= vramBase && cpu.HL < vramBase + TextVRAM::SIZE;
        uint32_t offset = cursorInBounds ? (cpu.HL - vramBase) : 0;
        int cursorRow = static_cast<int>(offset / TextVRAM::WIDTH);
        int cursorCol = static_cast<int>(offset % TextVRAM::WIDTH);

        if (config.useVideoConsole)
        {
            videoConsole.pushFrame(vram, attr, cursorRow, cursorCol, cursorInBounds);
            return;
        }

        // Весь кадр сначала собирается в памяти и уходит на экран
        // ОДНИМ write - иначе десятки-сотни отдельных << на std::cout
        // (по паре байт на символ кириллицы/псевдографики, плюс ANSI-
        // код на каждую смену цвета) могут превысить внутренний буфер
        // потока и вызвать НЕСКОЛЬКО настоящих системных вызовов
        // записи в консоль на один кадр - при частой перерисовке
        // (см. programRunning ниже) это ощутимо тормозит и саму
        // перерисовку, и (раз всё в одном потоке с cpu.step()) опрос
        // клавиатуры.
        std::ostringstream frame;

        // Прячем курсор перед перерисовкой - иначе он на мгновение
        // виден "прыгающим" в начало экрана перед каждым кадром
        frame << "\x1b[?25l\x1b[H";
        vram.render(&attr, frame);

        if (cursorInBounds)
        {
            frame << "\x1b[" << (cursorRow + 1) << ";" << (cursorCol + 1) << "H";
        }

        frame << "\x1b[?25h";

        std::cout << frame.str();
        std::cout.flush();
    };

    redraw();

    uint8_t lastKeyCount = 0;
    uint8_t lastBannerReady = 0;
    uint8_t lastDoneReady = 0;

    // Помимо перерисовки по изменению keyCount/bannerReady/doneReady
    // (нужно для мгновенного отклика печати в терминале) - отдельная,
    // по РЕАЛЬНОМУ времени, перерисовка раз в ~150 мс (тот же приём
    // throttling'а через steady_clock, что и в Keyboard::tick()), НО
    // только пока реально работает exec'нутая программа (programRunning,
    // 0x00010004, см. SHELL.ASM) - иначе программа, которая пишет прямо
    // в Text VRAM, но не трогает keyCount/bannerReady/doneReady
    // (например, игра на мини-C, опрашивающая клавиатуру напрямую через
    // peek(), а не через прерывания), была бы не видна на экране в
    // реальном времени.
    //
    // Гейт по programRunning принципиален: включать это ВСЕГДА (в том
    // числе на время обычной работы шелла) резко увеличивает нагрузку
    // и на практике тормозит печать баннера и опрос клавиатуры -
    // проверено на живую, регресс уже был и это его исправление.
    //
    // 150 мс (не 33/~30 кадров/сек, как было раньше) - тоже осознанно:
    // redraw() - это реальная перерисовка терминала (не просто запись
    // в файл), и на медленной консоли сам по себе может занимать
    // заметное время; 30 раз/сек этого хватало, чтобы синхронный вызов
    // redraw() съедал большую часть времени потока, в котором крутится
    // cpu.step()/опрос клавиатуры - отсюда и "клавиатура не реагирует".
    // SNAKE.MC двигает змейку раз в 120 мс - чаще этого перерисовывать
    // всё равно бессмысленно, кадр не меняется.
    auto lastRedraw = std::chrono::steady_clock::now();

    while (cpu.running)
    {
        cpu.step();

        uint8_t currentKeyCount = bus.read(0x00010000);
        uint8_t currentBannerReady = bus.read(0x00010002);
        uint8_t currentDoneReady = bus.read(0x00010003);
        uint8_t currentProgramRunning = bus.read(0x00010004);

        auto now = std::chrono::steady_clock::now();

        if (currentKeyCount != lastKeyCount ||
            currentBannerReady != lastBannerReady ||
            currentDoneReady != lastDoneReady ||
            (currentProgramRunning != 0 && now - lastRedraw >= std::chrono::milliseconds(150)))
        {
            lastKeyCount = currentKeyCount;
            lastBannerReady = currentBannerReady;
            lastDoneReady = currentDoneReady;
            lastRedraw = now;

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
