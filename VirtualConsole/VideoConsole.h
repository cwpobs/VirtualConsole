#pragma once

#include <atomic>
#include <cstdint>
#include <mutex>
#include <thread>

#define NOMINMAX       // иначе windows.h определит макросы min/max,
                        // которые ломают std::min/std::max везде, где
                        // транзитивно подключён этот заголовок
#include <Windows.h>   // HWND/WPARAM/LPARAM/LRESULT - для WindowProc ниже

class Keyboard;
class Mouse;
class TextVRAM;
class TextAttr;
class VideoCard;
class ConsoleLayer;

// Видеоконсоль: единственное графическое окно на весь процесс -
// текстовый режим 80x25 (символ CP866 + fg/bg атрибут, см.
// TextVRAM/TextAttr) и картинка VideoCard (320x240 + спрайты/тайлы/
// 3D, см. VideoCard.h) - это два слоя ОДНОЙ композиции, а не два
// отдельных окна. Программы не видят разницы: TextVRAM/TextAttr и
// регистры VideoCard пишутся через шину точно как раньше (см.
// main.cpp) - VideoConsole лишь общий рендерер их обоих, само не
// устройство шины (нет MMIO/регистров).
//
// Слой VideoCard - фон: если VideoCard::isActive() (между MODE_ON и
// MODE_OFF), его 320x240 (4:3) кадр вписывается в канву 640x400 (8:5)
// с сохранением пропорций и центрированием (чёрные поля по бокам) -
// см. compositeVideoCardLayer(). Нативное разрешение VideoCard/Gpu3D
// не меняем: оно зашито и в проекцию 3D, и в существующие GAMES/DEMOS.
//
// Слой текста - поверх, с ДВУМЯ правилами прозрачности (см.
// rasterize()):
//  - ячейка (' ', TextAttr::DEFAULT_ATTRIBUTE) - "нетронутая" после
//    CLEAR/загрузки - не рисуется вообще, целиком прозрачна;
//  - ячейка с фоном TextAttr::TRANSPARENT_BG - рисуется только сам
//    символ нужным цветом, фон не трогается (под ним виден слой
//    VideoCard/то, что уже было) - "прозрачный цвет фона" для ЛЮБОГО
//    символа, не только пробела.
// В обоих случаях снизу виден слой VideoCard/чёрный фон. Любая другая
// ячейка остаётся полностью непрозрачной, как раньше. Второе правило -
// готовый механизм HUD поверх графики в играх: обычный текст с
// TRANSPARENT_BG поверх активной VideoCard уже просто работает.
//
// Рисовать текстовый слой вообще или нет - решает ConsoleLayer (см.
// ConsoleLayer.h): VideoCard сама прячет его на MODE_ON и возвращает
// на MODE_OFF, а программа может включить его обратно по ходу работы
// через MMIO (poke(CONSOLE_VISIBLE, 1) в мини-C) - "комбинированный
// режим", когда текст и графика видны одновременно.
//
// Окно, message pump и OpenGL живут в отдельном std::thread,
// независимом от потока CPU. Между потоками - не общие указатели на
// TextVRAM/TextAttr/VideoCard (там нет мьютекса на стороне
// TextVRAM/TextAttr, а пишет в них поток CPU), а push-копия текста:
// main.cpp вызывает pushFrame() в тех же точках, где раньше вызывал
// ANSI-redraw() (см. main.cpp, throttling по 150 мс/keyCount), копия
// под мьютексом ложится в СВОЮ память устройства ("своя память для
// построения страницы" - см. ASSEMBLY.md, "VideoConsole"). VideoCard
// же сам потокобезопасен (framebufferMutex, isActive()/compositeFrame()
// можно звать из любого потока) - рендер-поток обращается к нему
// напрямую, копия не нужна.
class VideoConsole
{
public:

    static const int COLS = 80;
    static const int ROWS = 25;
    static const int CELL_W = 8;
    static const int CELL_H = 16;

    // keyboard - куда класть нажатия, пойманные окном (WM_CHAR/
    // WM_KEYDOWN), пока у него фокус ОС. videoCard - источник слоя
    // графики (см. compositeVideoCardLayer). consoleLayer - видим ли
    // текстовый слой вообще (см. ConsoleLayer.h). Ни один из
    // указателей не может быть nullptr. scale - целочисленный масштаб
    // пикселя окна (1 = 640x400, 2 = 1280x800 и т.д.) - глиф остаётся
    // резким при увеличении, т.к. рисуется как есть, без сглаживания
    // (см. renderThreadMain, glPixelZoom).
    VideoConsole(Keyboard* keyboard, Mouse* mouse, VideoCard* videoCard, ConsoleLayer* consoleLayer, int scale);
    ~VideoConsole();

    // Открывает окно и стартует рендер-поток - вызывается один раз из
    // main.cpp, когда конфигурация ВМ выбрала видеоконсоль (см.
    // VmConfig). Не влияет на TextVRAM/TextAttr и адресное
    // пространство шины.
    void start();

    // Копирует текущее содержимое vram/attr (2000+2000 байт) в
    // собственную память устройства под мьютексом и отмечает кадр как
    // изменившийся - рендер-поток перерисует его на следующей
    // итерации. cursorRow/cursorCol - позиция курсора в границах
    // COLSxROWS (тот же смысл, что HL-в-границах-VRAM у ANSI-redraw()
    // в main.cpp), cursorVisible - рисовать ли его вообще (совместимо
    // с выключенным курсором \x1b[?25l у обычной консоли).
    void pushFrame(const TextVRAM& vram, const TextAttr& attr,
        int cursorRow, int cursorCol, bool cursorVisible);

private:

    static LRESULT CALLBACK WindowProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam);

    void renderThreadMain();
    void rasterize(uint8_t* rgb) const;

    // Слой VideoCard (фон) - вписывает compositeFrame() (320x240) в
    // rgb (640x400) с сохранением пропорций, центрированием и чёрными
    // полями; если !videoCard->isActive() - просто заливает rgb
    // чёрным. Вызывается в renderThreadMain ПЕРЕД rasterize(), которая
    // рисует текст поверх и местами оставляет этот фон видимым (см.
    // правило прозрачности в комментарии класса).
    void compositeVideoCardLayer(uint8_t* rgb) const;

    Keyboard* keyboard;
    Mouse* mouse;
    VideoCard* videoCard;
    ConsoleLayer* consoleLayer;
    int scale;

    // Отслеживает, спрятан ли сейчас системный курсор (ShowCursor - это
    // счётчик показов/скрытий, не булев флаг - звать его на каждый
    // WM_MOUSEMOVE нельзя, нужно звать РОВНО один раз на переход
    // включено/выключено захвата мыши, см. WM_MOUSEMOVE в .cpp).
    bool mouseCaptured;

    std::thread renderThread;
    std::atomic<bool> stopRequested;

    std::mutex frameMutex;
    uint8_t chars[COLS * ROWS];
    uint8_t attrs[COLS * ROWS];
    int cursorRow;
    int cursorCol;
    bool cursorVisible;
    uint64_t frameGeneration;
};
