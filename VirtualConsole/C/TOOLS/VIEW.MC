// VIEW.MC - постраничный просмотрщик текстового файла на мини-C (см.
// ASSEMBLY.md, "Мини-C"). Имя файла приходит ПЕРВЫМ аргументом
// (CMD_ARGS_LEN/cmdArgs - см. ASSEMBLY.md, "Аргументы командной
// строки") - обычно запускается из C/TOOLS/FM.MC по F3 (см.
// view_selected_file() в FM.MC), но точно так же работает при ручном
// запуске из шелла: "exec view.mc ИМЯ.ТХТ" или (после "build view.mc")
// "view ИМЯ.ТХТ".
//
// Управление: стрелки Вверх/Вниз - предыдущая/следующая страница (24
// строки текста на страницу, 25-я строка экрана - статусная), Esc -
// выход (возврат в того, кто запустил - FM.MC или шелл).
//
// НЕ хранит файл в памяти - у Мини-C массив не может быть больше 255
// элементов (8-битный индекс), обычный текстовый файл в это не влезет.
// Вместо этого при каждой смене страницы файл открывается заново
// (OPEN_READ) и построчно (по '\n' = 10) пропускается нужное число
// строк, затем печатается следующая порция - дороже по количеству
// операций чтения, чем один проход, зато работает для файла любого
// размера и не тратит память программы. По той же причине (нет 16-бит
// арифметики - см. ASSEMBLY.md, "Мини-C") число строк для пропуска не
// считается умножением page*LINES_PER_PAGE (переполнилось бы уже при
// page>10 - 8 бит), а внешним циклом "по одной странице" с внутренним
// счётчиком 0-23 на страницу (тот же приём, что boot.asm/print_str
// используют для y*80 - см. ASSEMBLY.md).
//
// Собирается командой "build view.mc", запускается как "view ИМЯ".

#include "DISKIO.MC"
#include "STRLIB.MC"

const LINES_PER_PAGE = 24;   // строки 0-23 - текст, строка 24 - статус
const KEY_ESC = 27;
const KEY_UP = 72;
const KEY_DOWN = 80;

int currentPage;
int running;

int wait_ms(int ms) {
    poke(CLOCK_LOW, 0);
    while (peek(CLOCK_LOW) < ms) {
    }
    return 0;
}

int build_name_from_args(int diskId) {
    int i;
    i = 0;
    while (i < 12) {
        diskio_set_name_char(diskId, i, cmdArgs[i]);
        i = i + 1;
    }
    return 0;
}

int check_file_exists(int diskId) {
    diskio_cmd(diskId, DISKIO_OPEN_READ);
    if (diskio_status(diskId) == 2) { return 0; }
    diskio_cmd(diskId, DISKIO_CLOSE);
    return 1;
}

// Открывает файл заново, пропускает page страниц (по LINES_PER_PAGE
// строк каждая - счёт двойным циклом, без умножения, см. комментарий в
// начале файла), затем печатает следующую страницу построчно. Если
// файл кончился ещё во время пропуска - страницы не существует: экран
// не трогаем, закрываем файл, возвращаем 0 (вызывающий код не должен
// менять currentPage).
int render_page(int diskId, int page) {
    int p;
    int linesInPage;
    int ch;
    int x;
    int y;
    int eof;

    diskio_cmd(diskId, DISKIO_OPEN_READ);
    if (diskio_status(diskId) == 2) { return 0; }

    eof = 0;
    p = 0;
    while (p < page) {
        linesInPage = 0;
        while (linesInPage < LINES_PER_PAGE) {
            diskio_cmd(diskId, DISKIO_READ_BYTE);
            if (diskio_status(diskId) == 1) {
                eof = 1;
                linesInPage = LINES_PER_PAGE;
                p = page;
            } else {
                ch = diskio_data(diskId);
                if (ch == 10) { linesInPage = linesInPage + 1; }
            }
        }
        p = p + 1;
    }

    if (eof == 1) {
        diskio_cmd(diskId, DISKIO_CLOSE);
        return 0;
    }

    clear_screen();

    y = 0;
    x = 0;
    while (y < LINES_PER_PAGE) {
        diskio_cmd(diskId, DISKIO_READ_BYTE);
        if (diskio_status(diskId) == 1) {
            y = LINES_PER_PAGE;
        } else {
            ch = diskio_data(diskId);
            if (ch == 10) {
                y = y + 1;
                x = 0;
            } else {
                // '\r' (13, Windows CRLF) - НЕ печатать: на реальном
                // терминале сырой байт 13 - настоящий возврат каретки,
                // курсор прыгает в начало строки и всё, что печатается
                // дальше, накладывается на уже выведенное (тот же баг
                // чинили в EDIT.MC).
                if (ch != 13) {
                    if (x < 79) {
                        print_char(x, y, ch);
                        x = x + 1;
                    }
                }
            }
        }
    }

    diskio_cmd(diskId, DISKIO_CLOSE);
    return 1;
}

int draw_status() {
    int i;
    int ch;

    i = 0;
    while (i < 80) {
        set_color(i, 24, 0, 7);   // чёрным по белому - как F-панель FM.MC
        i = i + 1;
    }

    i = 0;
    while (i < 12) {
        ch = cmdArgs[i];
        if (ch == 0) { ch = 32; }
        print_char(i, 24, ch);
        i = i + 1;
    }

    print_str(14, 24, "PAGE");
    print_number3(19, 24, currentPage);
    print_str(30, 24, "Up/Down-page  Esc-exit");

    return 0;
}

int try_page(int diskId, int candidatePage) {
    if (render_page(diskId, candidatePage) == 1) {
        currentPage = candidatePage;
        draw_status();
        return 1;
    }
    return 0;
}

int main() {
    int diskId;
    int key;

    diskId = peek(EXEC_CHILD_DISK);
    build_name_from_args(diskId);

    if (check_file_exists(diskId) == 0) {
        clear_screen();
        print_str(0, 0, "file not found");
        wait_ms(2000);
        return 1;
    }

    currentPage = 0;
    render_page(diskId, 0);
    draw_status();

    running = 1;
    while (running == 1) {
        key = peek(KEYBOARD_DATA);

        if (key == KEY_ESC) { running = 0; }
        if (key == KEY_UP) {
            if (currentPage > 0) { try_page(diskId, currentPage - 1); }
        }
        if (key == KEY_DOWN) { try_page(diskId, currentPage + 1); }

        wait_ms(80);
    }

    return 0;
}
