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
class TextVRAM;
class TextAttr;

// Видеоконсоль: тот же текстовый режим 80x25 (символ CP866 + fg/bg
// атрибут), что и обычная консоль (см. TextVRAM/TextAttr), но
// рисуется пиксельно - битмап-шрифтом (см. Font8x16.h) в собственное
// графическое окно (Win32 + OpenGL/WGL), а не ANSI-последовательностями
// в окно консоли Windows. Программы не видят разницы: они по-прежнему
// пишут в TextVRAM/TextAttr через шину как раньше (см. main.cpp) -
// VideoConsole лишь ВТОРОЙ, альтернативный рендерер тех же данных, не
// устройство шины (нет MMIO/регистров).
//
// Архитектура - по образцу VideoCard (см. VideoCard.h): окно, message
// pump и OpenGL целиком живут в отдельном std::thread, независимом от
// потока CPU. Между потоками - не общий указатель на TextVRAM/TextAttr
// (там нет мьютекса, а пишет в них поток CPU), а push-копия: main.cpp
// вызывает pushFrame() в тех же точках, где раньше вызывал ANSI-
// redraw() (см. main.cpp, throttling по 150 мс/keyCount), копия под
// мьютексом ложится в СВОЮ память устройства ("своя память для
// построения страницы" - см. ASSEMBLY.md, "VideoConsole"), а рендер-
// поток растеризует её в пиксели независимо, на собственном таймере.
class VideoConsole
{
public:

    static const int COLS = 80;
    static const int ROWS = 25;
    static const int CELL_W = 8;
    static const int CELL_H = 16;

    // keyboard - куда класть нажатия, пойманные графическим окном
    // (WM_CHAR), пока у него фокус ОС - тот же приём, что у VideoCard
    // (см. VideoCard.h, WindowProc/injectKey). scale - целочисленный
    // масштаб пикселя окна (1 = 640x400, 2 = 1280x800 и т.д.) - глиф
    // остаётся резким при увеличении, т.к. рисуется как есть, без
    // сглаживания (см. renderThreadMain, glPixelZoom).
    VideoConsole(Keyboard* keyboard, int scale);
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

    Keyboard* keyboard;
    int scale;

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
