#include "VideoCard.h"

#include <cstring>

#include <Windows.h>
#include <GL/gl.h>

#pragma comment(lib, "opengl32.lib")
#pragma comment(lib, "gdi32.lib")
#pragma comment(lib, "user32.lib")

namespace
{
    const wchar_t* WINDOW_CLASS_NAME = L"VirtualConsoleVideoCard";

    LRESULT CALLBACK WindowProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam)
    {
        if (msg == WM_CLOSE || msg == WM_DESTROY)
        {
            // Пользователь закрыл окно крестиком - не подвешиваем
            // рендер-поток, он сам заметит WM_QUIT в своём цикле
            // сообщений и завершится (см. renderThreadMain).
            PostQuitMessage(0);
            return 0;
        }

        return DefWindowProc(hwnd, msg, wParam, lParam);
    }
}

VideoCard::VideoCard()
    : windowOpen(false), stopRequested(false)
{
    xLow = xHigh = yLow = yHigh = 0;
    wLow = wHigh = hLow = hHigh = 0;
    r = g = b = 0;
    status = 0;

    for (int i = 0; i < FB_SIZE; i++)
    {
        framebuffer[i] = 0;
    }
}

VideoCard::~VideoCard()
{
    modeOff();
}

uint16_t VideoCard::regX() const { return static_cast<uint16_t>(xLow) | (static_cast<uint16_t>(xHigh) << 8); }
uint16_t VideoCard::regY() const { return static_cast<uint16_t>(yLow) | (static_cast<uint16_t>(yHigh) << 8); }
uint16_t VideoCard::regW() const { return static_cast<uint16_t>(wLow) | (static_cast<uint16_t>(wHigh) << 8); }
uint16_t VideoCard::regH() const { return static_cast<uint16_t>(hLow) | (static_cast<uint16_t>(hHigh) << 8); }

uint8_t VideoCard::read(uint32_t address)
{
    switch (address)
    {
    case REG_X_LOW: return xLow;
    case REG_X_HIGH: return xHigh;
    case REG_Y_LOW: return yLow;
    case REG_Y_HIGH: return yHigh;
    case REG_W_LOW: return wLow;
    case REG_W_HIGH: return wHigh;
    case REG_H_LOW: return hLow;
    case REG_H_HIGH: return hHigh;
    case REG_R: return r;
    case REG_G: return g;
    case REG_B: return b;
    case REG_STATUS: return status;
    default: return 0;
    }
}

void VideoCard::write(uint32_t address, uint8_t value)
{
    switch (address)
    {
    case REG_X_LOW: xLow = value; return;
    case REG_X_HIGH: xHigh = value; return;
    case REG_Y_LOW: yLow = value; return;
    case REG_Y_HIGH: yHigh = value; return;
    case REG_W_LOW: wLow = value; return;
    case REG_W_HIGH: wHigh = value; return;
    case REG_H_LOW: hLow = value; return;
    case REG_H_HIGH: hHigh = value; return;
    case REG_R: r = value; return;
    case REG_G: g = value; return;
    case REG_B: b = value; return;

    case REG_COMMAND:
        switch (value)
        {
        case 1: modeOn(); break;
        case 2: modeOff(); break;
        case 3: clear(); break;
        case 4: setPixel(); break;
        case 5: fillRect(); break;
        default: break;
        }
        return;

    default:
        return;
    }
}

void VideoCard::clear()
{
    std::lock_guard<std::mutex> lock(framebufferMutex);

    for (int i = 0; i < FB_SIZE; i += CHANNELS)
    {
        framebuffer[i] = r;
        framebuffer[i + 1] = g;
        framebuffer[i + 2] = b;
    }

    status = 0;
}

void VideoCard::setPixel()
{
    uint16_t x = regX();
    uint16_t y = regY();

    if (x >= WIDTH || y >= HEIGHT)
    {
        status = 1;
        return;
    }

    std::lock_guard<std::mutex> lock(framebufferMutex);

    int index = (y * WIDTH + x) * CHANNELS;
    framebuffer[index] = r;
    framebuffer[index + 1] = g;
    framebuffer[index + 2] = b;

    status = 0;
}

void VideoCard::fillRect()
{
    uint16_t x = regX();
    uint16_t y = regY();
    uint16_t w = regW();
    uint16_t h = regH();

    if (x >= WIDTH || y >= HEIGHT)
    {
        status = 1;
        return;
    }

    uint16_t x2 = x + w;
    uint16_t y2 = y + h;
    if (x2 > WIDTH) x2 = WIDTH;
    if (y2 > HEIGHT) y2 = HEIGHT;

    std::lock_guard<std::mutex> lock(framebufferMutex);

    for (uint16_t py = y; py < y2; py++)
    {
        int rowBase = py * WIDTH * CHANNELS;
        for (uint16_t px = x; px < x2; px++)
        {
            int index = rowBase + px * CHANNELS;
            framebuffer[index] = r;
            framebuffer[index + 1] = g;
            framebuffer[index + 2] = b;
        }
    }

    status = 0;
}

void VideoCard::modeOn()
{
    if (windowOpen)
    {
        return;
    }

    // Поток от предыдущего сеанса мог уже сам завершиться (например,
    // окно закрыли крестиком - см. WindowProc/renderThreadMain), но
    // остаться незаджойненным - std::thread обязательно должен быть
    // либо joined, либо detached до уничтожения, иначе std::terminate.
    if (renderThread.joinable())
    {
        renderThread.join();
    }

    stopRequested = false;
    windowOpen = true;

    renderThread = std::thread(&VideoCard::renderThreadMain, this);
}

void VideoCard::modeOff()
{
    stopRequested = true;

    if (renderThread.joinable())
    {
        renderThread.join();
    }

    windowOpen = false;
}

void VideoCard::renderThreadMain()
{
    HINSTANCE hInstance = GetModuleHandle(nullptr);

    WNDCLASSEXW wc = {};
    wc.cbSize = sizeof(wc);
    wc.style = CS_OWNDC;
    wc.lpfnWndProc = WindowProc;
    wc.hInstance = hInstance;
    wc.hCursor = LoadCursor(nullptr, IDC_ARROW);
    wc.lpszClassName = WINDOW_CLASS_NAME;
    RegisterClassExW(&wc);   // повторная регистрация при следующем MODE_ON молча игнорируется (ERROR_CLASS_ALREADY_EXISTS)

    const int windowWidth = WIDTH * 2;
    const int windowHeight = HEIGHT * 2;

    RECT rect = { 0, 0, windowWidth, windowHeight };
    AdjustWindowRect(&rect, WS_OVERLAPPEDWINDOW & ~WS_THICKFRAME & ~WS_MAXIMIZEBOX, FALSE);

    HWND hwnd = CreateWindowExW(
        0, WINDOW_CLASS_NAME, L"VirtualConsole - Video",
        (WS_OVERLAPPEDWINDOW & ~WS_THICKFRAME & ~WS_MAXIMIZEBOX) | WS_VISIBLE,
        CW_USEDEFAULT, CW_USEDEFAULT,
        rect.right - rect.left, rect.bottom - rect.top,
        nullptr, nullptr, hInstance, nullptr);

    if (hwnd == nullptr)
    {
        windowOpen = false;
        return;
    }

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
    glOrtho(0, WIDTH, 0, HEIGHT, -1, 1);
    glMatrixMode(GL_MODELVIEW);
    glLoadIdentity();

    // glDrawPixels рисует строки вверх от raster position - зеркалим
    // по Y (отрицательный zoom), чтобы строка 0 буфера (верх кадра)
    // оказалась вверху окна, а не внизу.
    glPixelZoom(2.0f, -2.0f);
    glPixelStorei(GL_UNPACK_ALIGNMENT, 1);

    uint8_t staging[FB_SIZE];

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

        {
            std::lock_guard<std::mutex> lock(framebufferMutex);
            memcpy(staging, framebuffer, FB_SIZE);
        }

        glClear(GL_COLOR_BUFFER_BIT);
        glRasterPos2i(0, HEIGHT);
        glDrawPixels(WIDTH, HEIGHT, GL_RGB, GL_UNSIGNED_BYTE, staging);
        SwapBuffers(hdc);

        Sleep(16);   // ~60 FPS - не гоняем поток на пределе ради статичного кадра
    }

    wglMakeCurrent(nullptr, nullptr);
    wglDeleteContext(hglrc);
    ReleaseDC(hwnd, hdc);
    DestroyWindow(hwnd);

    windowOpen = false;
}
