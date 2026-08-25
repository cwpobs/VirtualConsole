#include "VideoConsole.h"
#include "Keyboard.h"
#include "Mouse.h"
#include "TextVRAM.h"
#include "TextAttr.h"
#include "Font8x16.h"
#include "VideoCard.h"
#include "ConsoleLayer.h"

#include <cstring>
#include <utility>

#define NOMINMAX
#include <Windows.h>
#include <GL/gl.h>

#pragma comment(lib, "opengl32.lib")
#pragma comment(lib, "gdi32.lib")
#pragma comment(lib, "user32.lib")

namespace
{
    const wchar_t* WINDOW_CLASS_NAME = L"VirtualConsoleVideoConsole";

    // DOS extended-скан-коды - те же числа, что вторым байтом отдал бы
    // _getch() реальной консоли (см. Keyboard::tick()), и что уже зашиты
    // константами в C/TOOLS/FM.MC (KEY_UP/KEY_DOWN/FKEY_F2..FKEY_F10) и
    // C/TOOLS/EDIT.MC (KEY_LEFT/KEY_RIGHT/KEY_HOME/...). WM_CHAR/
    // TranslateMessage эти клавиши вообще не транслирует (только
    // печатаемые символы и десяток управляющих кодов) - без этой
    // таблицы стрелки/F-клавиши в окне VideoConsole не доходили бы до
    // Keyboard, хотя обычный текстовый ввод (через WM_CHAR ниже)
    // работал бы нормально - именно этим объяснялось "клавиатура не
    // реагирует в FM, но в шелле работает".
    int extendedKeyCode(WPARAM vk)
    {
        switch (vk)
        {
        case VK_UP: return 72;
        case VK_DOWN: return 80;
        case VK_LEFT: return 75;
        case VK_RIGHT: return 77;
        case VK_HOME: return 71;
        case VK_END: return 79;
        case VK_PRIOR: return 73;   // PgUp
        case VK_NEXT: return 81;    // PgDn
        case VK_DELETE: return 83;
        case VK_F1: return 59;
        case VK_F2: return 60;
        case VK_F3: return 61;
        case VK_F4: return 62;
        case VK_F5: return 63;
        case VK_F6: return 64;
        case VK_F7: return 65;
        case VK_F8: return 66;
        case VK_F9: return 67;
        case VK_F10: return 68;
        default: return -1;
        }
    }

    // Ведущий байт двухбайтовой extended-последовательности _getch() -
    // 0 для F1-F10, 0xE0 (224) для остальных (стрелки/Home/End/PgUp/
    // PgDn/Delete) - реальная консоль всегда шлёт его ПЕРЕД самим кодом
    // клавиши (см. Keyboard::tick(), которое ретранслирует _getch() как
    // есть). Без этого лидирующего байта потребители вроде
    // C/TOOLS/EDIT.MC (см. его pendingExtended, EDIT.MC:98-105) не
    // могут отличить настоящую печатную букву от спецклавиши - код
    // KEY_UP=72 численно совпадает с 'H' и т.п. C/TOOLS/FM.MC лидирующий
    // байт просто безвредно игнорирует (см. FM.MC:56-60), поэтому один
    // и тот же приём безопасен для обоих потребителей.
    uint8_t extendedKeyPrefix(WPARAM vk)
    {
        if (vk >= VK_F1 && vk <= VK_F10)
        {
            return 0;
        }

        return 0xE0;
    }

    const int PIXEL_WIDTH = VideoConsole::COLS * VideoConsole::CELL_W;   // 640
    const int PIXEL_HEIGHT = VideoConsole::ROWS * VideoConsole::CELL_H;  // 400

    // Классический 16-цветный EGA/CGA-набор - тот же порядок, что
    // документирован у TextAttr (см. TextAttr.h: "младший нибл -
    // цвет символа (0-15) ... классический PC-формат", 0x07 =
    // светло-серый на чёрном).
    const uint8_t PALETTE[16][3] =
    {
        {   0,   0,   0 }, // 0 чёрный
        {   0,   0, 170 }, // 1 синий
        {   0, 170,   0 }, // 2 зелёный
        {   0, 170, 170 }, // 3 голубой
        { 170,   0,   0 }, // 4 красный
        { 170,   0, 170 }, // 5 малиновый
        { 170,  85,   0 }, // 6 коричневый
        { 170, 170, 170 }, // 7 светло-серый (по умолчанию)
        {  85,  85,  85 }, // 8 тёмно-серый
        {  85,  85, 255 }, // 9 светло-синий
        {  85, 255,  85 }, // 10 светло-зелёный
        {  85, 255, 255 }, // 11 светло-голубой
        { 255,  85,  85 }, // 12 светло-красный
        { 255,  85, 255 }, // 13 светло-малиновый
        { 255, 255,  85 }, // 14 жёлтый
        { 255, 255, 255 }, // 15 белый
    };
}

LRESULT CALLBACK VideoConsole::WindowProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam)
{
    if (msg == WM_CLOSE || msg == WM_DESTROY)
    {
        // Не подвешиваем рендер-поток - он сам заметит WM_QUIT в своём
        // цикле сообщений и завершится (см. renderThreadMain).
        PostQuitMessage(0);
        return 0;
    }

    if (msg == WM_KEYDOWN)
    {
        // Стрелки/Home/End/PgUp/PgDn/Delete/F1-F10 (без Alt) - см.
        // extendedKeyCode выше. Остальные клавиши тут не трогаем -
        // печатаемые символы и Enter/Backspace/Tab/Esc/Ctrl+буква
        // по-прежнему идут через WM_CHAR ниже (TranslateMessage сам
        // решает, для чего его генерировать), двойной инжекции не
        // будет - WM_CHAR для этих кодов клавиш не порождается вообще.
        int code = extendedKeyCode(wParam);

        if (code >= 0)
        {
            VideoConsole* self = reinterpret_cast<VideoConsole*>(GetWindowLongPtr(hwnd, GWLP_USERDATA));

            if (self != nullptr && self->keyboard != nullptr)
            {
                // Двухбайтовая последовательность (префикс, потом код) -
                // см. extendedKeyPrefix выше; без префикса EDIT.MC не
                // отличает стрелку от буквы с тем же числовым кодом.
                self->keyboard->injectKey(extendedKeyPrefix(wParam));
                self->keyboard->injectKey(static_cast<uint8_t>(code));
            }

            return 0;
        }
    }

    if (msg == WM_SYSKEYDOWN)
    {
        // Alt+F1/Alt+F2 (смена диска панели в FM.MC, см. ALT_F1/
        // ALT_F2) - Windows шлёт F-клавиши с зажатым Alt именно этим
        // сообщением, не WM_KEYDOWN. Остальные Alt-комбинации (Alt+F4
        // и т.п.) не трогаем - падают в DefWindowProc, системные
        // акселераторы не ломаем.
        int code = -1;

        if (wParam == VK_F1) { code = 104; }
        else if (wParam == VK_F2) { code = 105; }

        if (code >= 0)
        {
            VideoConsole* self = reinterpret_cast<VideoConsole*>(GetWindowLongPtr(hwnd, GWLP_USERDATA));

            if (self != nullptr && self->keyboard != nullptr)
            {
                self->keyboard->injectKey(static_cast<uint8_t>(code));
            }

            return 0;
        }
    }

    if (msg == WM_MOUSEMOVE)
    {
        // Захват мыши (FPS-style mouse-look): пока Mouse::CONTROL включён
        // (программа сама решает, poke(MOUSE_CONTROL,1)), курсор прячется
        // и удерживается в центре клиентской области - дельта копится как
        // разница между текущей позицией сообщения и этим центром, а не
        // между последовательными сообщениями, поэтому не нужно хранить
        // "прошлую" позицию отдельно (SetCursorPos ниже сам возвращает
        // курсор обратно перед следующим сообщением).
        VideoConsole* self = reinterpret_cast<VideoConsole*>(GetWindowLongPtr(hwnd, GWLP_USERDATA));

        if (self != nullptr && self->mouse != nullptr)
        {
            bool captureRequested = self->mouse->isCaptureEnabled();

            RECT client;
            GetClientRect(hwnd, &client);
            int centerX = (client.right - client.left) / 2;
            int centerY = (client.bottom - client.top) / 2;

            int curX = static_cast<short>(LOWORD(lParam));
            int curY = static_cast<short>(HIWORD(lParam));

            if (captureRequested)
            {
                if (!self->mouseCaptured)
                {
                    ShowCursor(FALSE);
                    self->mouseCaptured = true;
                }
                else
                {
                    int dx = curX - centerX;
                    int dy = curY - centerY;

                    if (dx != 0 || dy != 0)
                    {
                        self->mouse->injectMouseMove(dx, dy);
                    }
                }

                POINT center = { centerX, centerY };
                ClientToScreen(hwnd, &center);
                SetCursorPos(center.x, center.y);
            }
            else if (self->mouseCaptured)
            {
                ShowCursor(TRUE);
                self->mouseCaptured = false;
            }
        }

        return 0;
    }

    if (msg == WM_LBUTTONDOWN || msg == WM_LBUTTONUP ||
        msg == WM_RBUTTONDOWN || msg == WM_RBUTTONUP)
    {
        VideoConsole* self = reinterpret_cast<VideoConsole*>(GetWindowLongPtr(hwnd, GWLP_USERDATA));

        if (self != nullptr && self->mouse != nullptr)
        {
            bool down = (msg == WM_LBUTTONDOWN || msg == WM_RBUTTONDOWN);
            int bit = (msg == WM_LBUTTONDOWN || msg == WM_LBUTTONUP) ? 0 : 1;
            self->mouse->setButton(bit, down);
        }

        return 0;
    }

    if (msg == WM_CHAR)
    {
        // Окно видеоконсоли живёт своим отдельным HWND - если у него
        // фокус ОС, консольные _kbhit()/_getch() у Keyboard ничего не
        // получают. Ловим нажатия сами и кладём их в ту же очередь
        // Keyboard, что и обычный консольный ввод.
        VideoConsole* self = reinterpret_cast<VideoConsole*>(GetWindowLongPtr(hwnd, GWLP_USERDATA));

        if (self != nullptr && self->keyboard != nullptr)
        {
            wchar_t wch = static_cast<wchar_t>(wParam);
            uint8_t byte;

            if (wch < 128)
            {
                byte = static_cast<uint8_t>(wch);
            }
            else
            {
                char converted = 0;
                WideCharToMultiByte(866, 0, &wch, 1, &converted, 1, nullptr, nullptr);
                byte = static_cast<uint8_t>(converted);
            }

            self->keyboard->injectKey(byte);
        }

        return 0;
    }

    return DefWindowProc(hwnd, msg, wParam, lParam);
}

VideoConsole::VideoConsole(Keyboard* keyboard, Mouse* mouse, VideoCard* videoCard, ConsoleLayer* consoleLayer, int scale)
    : keyboard(keyboard), mouse(mouse), videoCard(videoCard), consoleLayer(consoleLayer), scale(scale),
    mouseCaptured(false), stopRequested(false),
    cursorRow(0), cursorCol(0), cursorVisible(false), frameGeneration(0)
{
    for (int i = 0; i < COLS * ROWS; i++)
    {
        chars[i] = ' ';
        attrs[i] = TextAttr::DEFAULT_ATTRIBUTE;
    }
}

VideoConsole::~VideoConsole()
{
    stopRequested = true;

    if (renderThread.joinable())
    {
        renderThread.join();
    }
}

void VideoConsole::start()
{
    if (renderThread.joinable())
    {
        return; // уже запущена
    }

    stopRequested = false;
    renderThread = std::thread(&VideoConsole::renderThreadMain, this);
}

void VideoConsole::pushFrame(const TextVRAM& vram, const TextAttr& attr,
    int cursorRowIn, int cursorColIn, bool cursorVisibleIn)
{
    std::lock_guard<std::mutex> lock(frameMutex);

    for (int i = 0; i < COLS * ROWS; i++)
    {
        chars[i] = vram.charAt(i);
        attrs[i] = attr.attributeAt(i);
    }

    cursorRow = cursorRowIn;
    cursorCol = cursorColIn;
    cursorVisible = cursorVisibleIn;

    frameGeneration++;
}

void VideoConsole::rasterize(uint8_t* rgb) const
{
    // Вызывающий (renderThreadMain) уже держит frameMutex - см.
    // компоновку у VideoCard::compositeSprites про тот же приём.
    //
    // Мигание курсора - по системным часам самого рендер-потока, а не
    // по данным из pushFrame - курсору не нужен отдельный "толчок"
    // кадра, чтобы мигать, пока программа ничего не печатает.
    bool blinkOn = ((GetTickCount64() / 500) % 2) == 0;

    for (int row = 0; row < ROWS; row++)
    {
        for (int col = 0; col < COLS; col++)
        {
            int cell = row * COLS + col;
            uint8_t ch = chars[cell];
            uint8_t attribute = attrs[cell];

            // "Нетронутая" ячейка (пробел, дефолтный атрибут - т.е.
            // состояние сразу после CLEAR/загрузки) - прозрачна, не
            // трогаем rgb вообще: под ней виден слой VideoCard (или
            // чёрный фон), см. compositeVideoCardLayer, вызванный
            // раньше в renderThreadMain, и комментарий класса про
            // правило прозрачности. Курсор поверх прозрачной ячейки
            // всё равно должен быть виден - его ОТДЕЛЬНО проверяем
            // ниже, до пропуска.
            bool cursorHere = cursorVisible && blinkOn &&
                row == cursorRow && col == cursorCol;

            if (ch == ' ' && attribute == TextAttr::DEFAULT_ATTRIBUTE && !cursorHere)
            {
                continue;
            }

            int fg = attribute & 0x0F;
            int bg = (attribute >> 4) & 0x0F;

            if (cursorHere)
            {
                std::swap(fg, bg);
            }

            // TRANSPARENT_BG (см. TextAttr.h) - фон этой ячейки не
            // рисуем вообще, только сам глиф нужным цветом символа;
            // под фоном остаётся то, что там уже было (слой VideoCard
            // или чёрный) - вот и "прозрачный цвет фона". У символа
            // без единого закрашенного пикселя (пробел) это даёт
            // полностью невидимую ячейку - отдельного случая не нужно.
            bool bgTransparent = (bg == TextAttr::TRANSPARENT_BG);

            const uint8_t* fgColor = PALETTE[fg];
            const uint8_t* bgColor = PALETTE[bg];

            const uint8_t* glyph = &FONT_8X16[static_cast<int>(ch) * CELL_H];

            int baseX = col * CELL_W;
            int baseY = row * CELL_H;

            for (int gy = 0; gy < CELL_H; gy++)
            {
                uint8_t bits = glyph[gy];
                int py = baseY + gy;

                for (int gx = 0; gx < CELL_W; gx++)
                {
                    bool on = (bits & (0x80 >> gx)) != 0;

                    if (!on && bgTransparent)
                    {
                        continue;
                    }

                    int px = baseX + gx;
                    const uint8_t* color = on ? fgColor : bgColor;

                    int dst = (py * PIXEL_WIDTH + px) * 3;
                    rgb[dst] = color[0];
                    rgb[dst + 1] = color[1];
                    rgb[dst + 2] = color[2];
                }
            }
        }
    }
}

void VideoConsole::compositeVideoCardLayer(uint8_t* rgb) const
{
    if (!videoCard->isActive())
    {
        memset(rgb, 0, static_cast<size_t>(PIXEL_WIDTH) * PIXEL_HEIGHT * 3);
        return;
    }

    static uint8_t cardFrame[VideoCard::WIDTH * VideoCard::HEIGHT * VideoCard::CHANNELS];
    videoCard->compositeFrame(cardFrame);

    // Вписываем 320x240 (4:3) в 640x400 (8:5) с сохранением пропорций -
    // по высоте (лимитирующее измерение, scale ~1.667) картинка
    // заполняет канву целиком, по ширине остаются чёрные поля
    // (пилларбокс) слева/справа - см. комментарий класса. Метод -
    // "ближайший сосед" (без сглаживания), под стать пиксель-арту
    // VideoCard и уже принятому подходу к масштабированию шрифта.
    double scale = (PIXEL_WIDTH / static_cast<double>(VideoCard::WIDTH) <
        PIXEL_HEIGHT / static_cast<double>(VideoCard::HEIGHT))
        ? PIXEL_WIDTH / static_cast<double>(VideoCard::WIDTH)
        : PIXEL_HEIGHT / static_cast<double>(VideoCard::HEIGHT);

    int scaledW = static_cast<int>(VideoCard::WIDTH * scale);
    int scaledH = static_cast<int>(VideoCard::HEIGHT * scale);
    int offsetX = (PIXEL_WIDTH - scaledW) / 2;
    int offsetY = (PIXEL_HEIGHT - scaledH) / 2;

    for (int py = 0; py < PIXEL_HEIGHT; py++)
    {
        int cardY = py - offsetY;

        if (cardY < 0 || cardY >= scaledH)
        {
            memset(&rgb[(py * PIXEL_WIDTH) * 3], 0, static_cast<size_t>(PIXEL_WIDTH) * 3);
            continue;
        }

        int srcY = cardY * VideoCard::HEIGHT / scaledH;

        for (int px = 0; px < PIXEL_WIDTH; px++)
        {
            int cardX = px - offsetX;
            int dst = (py * PIXEL_WIDTH + px) * 3;

            if (cardX < 0 || cardX >= scaledW)
            {
                rgb[dst] = 0;
                rgb[dst + 1] = 0;
                rgb[dst + 2] = 0;
                continue;
            }

            int srcX = cardX * VideoCard::WIDTH / scaledW;
            int src = (srcY * VideoCard::WIDTH + srcX) * VideoCard::CHANNELS;

            rgb[dst] = cardFrame[src];
            rgb[dst + 1] = cardFrame[src + 1];
            rgb[dst + 2] = cardFrame[src + 2];
        }
    }
}

void VideoConsole::renderThreadMain()
{
    HINSTANCE hInstance = GetModuleHandle(nullptr);

    WNDCLASSEXW wc = {};
    wc.cbSize = sizeof(wc);
    wc.style = CS_OWNDC;
    wc.lpfnWndProc = &VideoConsole::WindowProc;
    wc.hInstance = hInstance;
    wc.hCursor = LoadCursor(nullptr, IDC_ARROW);
    wc.lpszClassName = WINDOW_CLASS_NAME;
    RegisterClassExW(&wc);   // повторная регистрация молча игнорируется (ERROR_CLASS_ALREADY_EXISTS)

    const int windowWidth = PIXEL_WIDTH * scale;
    const int windowHeight = PIXEL_HEIGHT * scale;

    RECT rect = { 0, 0, windowWidth, windowHeight };
    AdjustWindowRect(&rect, WS_OVERLAPPEDWINDOW & ~WS_THICKFRAME & ~WS_MAXIMIZEBOX, FALSE);

    HWND hwnd = CreateWindowExW(
        0, WINDOW_CLASS_NAME, L"VirtualConsole - Video Console",
        (WS_OVERLAPPEDWINDOW & ~WS_THICKFRAME & ~WS_MAXIMIZEBOX) | WS_VISIBLE,
        CW_USEDEFAULT, CW_USEDEFAULT,
        rect.right - rect.left, rect.bottom - rect.top,
        nullptr, nullptr, hInstance, nullptr);

    if (hwnd == nullptr)
    {
        return;
    }

    // Чтобы WindowProc (статический метод) мог достать этот экземпляр
    // и положить нажатую клавишу в keyboard - см. WM_CHAR выше.
    SetWindowLongPtr(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(this));

    HDC hdc = GetDC(hwnd);

    PIXELFORMATDESCRIPTOR pfd = {};
    pfd.nSize = sizeof(pfd);
    pfd.nVersion = 1;
    pfd.dwFlags = PFD_DRAW_TO_WINDOW | PFD_SUPPORT_OPENGL | PFD_DOUBLEBUFFER;
    pfd.iPixelType = PFD_TYPE_RGBA;
    pfd.cColorBits = 24;
    pfd.iLayerType = PFD_MAIN_PLANE;

    int pixelFormat = ChoosePixelFormat(hdc, &pfd);
    SetPixelFormat(hdc, pixelFormat, &pfd);

    HGLRC hglrc = wglCreateContext(hdc);
    wglMakeCurrent(hdc, hglrc);

    glViewport(0, 0, windowWidth, windowHeight);
    glMatrixMode(GL_PROJECTION);
    glLoadIdentity();
    glOrtho(0, PIXEL_WIDTH, 0, PIXEL_HEIGHT, -1, 1);
    glMatrixMode(GL_MODELVIEW);
    glLoadIdentity();

    // glDrawPixels рисует строки вверх от raster position - зеркалим
    // по Y (отрицательный zoom), как VideoCard.cpp, renderThreadMain.
    glPixelZoom(static_cast<float>(scale), -static_cast<float>(scale));
    glPixelStorei(GL_UNPACK_ALIGNMENT, 1);

    static uint8_t staging[PIXEL_WIDTH * PIXEL_HEIGHT * 3];
    uint64_t lastRasterized = static_cast<uint64_t>(-1);
    bool lastShowText = true;

    while (!stopRequested)
    {
        MSG msg;
        bool quitPosted = false;

        while (PeekMessage(&msg, nullptr, 0, 0, PM_REMOVE))
        {
            if (msg.message == WM_QUIT)
            {
                quitPosted = true;
            }

            TranslateMessage(&msg);
            DispatchMessage(&msg);
        }

        if (quitPosted)
        {
            break;
        }

        // Пока VideoCard активна, её кадр может меняться каждый тик
        // (спрайты/тайлы/3D двигаются) без единого изменения текста -
        // frameGeneration тут не помощник, перерисовываем каждую
        // итерацию, как и при видимом мигающем курсоре. showText -
        // видимость текстового слоя (см. ConsoleLayer.h) - сравниваем
        // с прошлым кадром отдельно, чтобы сам факт включения/
        // выключения консоли тоже вызывал перерисовку, даже если
        // ничего больше не изменилось.
        bool videoCardActive = videoCard->isActive();
        bool showText = consoleLayer->isVisible();
        bool needRedraw;

        {
            std::lock_guard<std::mutex> lock(frameMutex);
            needRedraw = (frameGeneration != lastRasterized) || cursorVisible ||
                videoCardActive || (showText != lastShowText);

            if (needRedraw)
            {
                compositeVideoCardLayer(staging);

                if (showText)
                {
                    rasterize(staging);
                }

                lastRasterized = frameGeneration;
                lastShowText = showText;
            }
        }

        if (needRedraw)
        {
            glClear(GL_COLOR_BUFFER_BIT);
            glRasterPos2i(0, PIXEL_HEIGHT);
            glDrawPixels(PIXEL_WIDTH, PIXEL_HEIGHT, GL_RGB, GL_UNSIGNED_BYTE, staging);
            SwapBuffers(hdc);
        }

        // ~60 FPS - пока курсор видим, needRedraw выше true каждую
        // итерацию (нужно для мигания), иначе растеризация
        // пропускается, если содержимое не менялось с прошлого кадра
        // (frameGeneration не изменился) - статичный экран не грузит
        // поток впустую.
        Sleep(16);
    }

    wglMakeCurrent(nullptr, nullptr);
    wglDeleteContext(hglrc);
    ReleaseDC(hwnd, hdc);
    DestroyWindow(hwnd);
}
