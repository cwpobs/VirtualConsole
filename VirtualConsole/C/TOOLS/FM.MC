// FM.MC - двухпанельный файловый менеджер (аналог Norton Commander)
// на мини-C (см. ASSEMBLY.md, "Мини-C"). Левая панель - ВСЕГДА диск
// C, правая - ВСЕГДА диск D (не выбирается пользователем): у каждого
// Disk ровно один currentDir - если бы обе панели могли смотреть один
// и тот же диск, перемещение по одной панели сбивало бы позицию
// другой. Фиксация панель-диск обходит это естественно (в VM ровно
// два физических диска).
//
// Работает с диском НАПРЯМУЮ через poke/peek теми же MMIO-регистрами,
// что уже использует cmd_dir/cmd_copy в SHELL.ASM (LIST_FIRST/
// LIST_NEXT/CHDIR/CHDIR_UP/OPEN_READ/READ_BYTE/OPEN_WRITE/WRITE_BYTE/
// CLOSE) - SHELL.ASM не тронут вообще, это отдельная программа.
//
// Управление: Tab - переключить панель, W/S - вверх/вниз по списку,
// Enter - зайти в папку, Backspace - подняться на уровень выше,
// Ctrl+Q - выход. Внизу экрана - подсказка F1-F10 в стиле Norton
// Commander - реально работает пока только F5 (Copy), остальные -
// только подписи (v1, задел на будущее: F3 View, F4 Edit, F6 Move,
// F7 MkDir, F8 Del и т.д.).
//
// F-клавиши на этой клавиатуре (через _getch()) приходят ДВУМЯ
// байтами - сначала 0, потом код клавиши (F1=59 ... F10=68) - первый
// байт неотличим от "очередь пуста" (см. ASSEMBLY.md, "Keyboard") и
// просто безвредно проглатывается обычным опросом; реальный код
// клавиши приходит следующим чтением сам по себе.
//
// Собирается командой "build fm.mc", запускается как "fm".

const KEY_DATA = 0xF0000005;
const CLOCK_LOW = 0xF0000FFC;

const FKEY_F5 = 63;   // Copy

const C_CMD = 0xF00007F2;
const C_STATUS = 0xF00007F3;
const C_DATA = 0xF00007F4;

const D_CMD = 0xF0000805;
const D_STATUS = 0xF0000806;
const D_DATA = 0xF0000807;

// NAME - 12 байт, индекс рантайм (0-11) - poke/peek константный адрес
// тут не подходит, нужен маппированный массив (см. ASSEMBLY.md).
int diskCName[12] = 0xF00007E6;
int diskDName[12] = 0xF00007F9;

const MAX_FILES = 18;

const COLOR_FILE = 15;    // ярко-белый
const COLOR_DIR  = 14;    // ярко-голубой
const COLOR_SEL  = 10;    // ярко-зелёный - выбранная строка
const COLOR_HEAD_ACTIVE   = 10;   // ярко-зелёный - активная панель
const COLOR_HEAD_INACTIVE = 7;    // обычный белый - неактивная

int leftNames[216];    // 18 * 12
int leftIsDir[18];
int leftCount;
int leftSel;

int rightNames[216];
int rightIsDir[18];
int rightCount;
int rightSel;

int activeRight;   // 0 = активна левая панель, 1 = правая

int wait_ms(int ms) {
    poke(CLOCK_LOW, 0);
    while (peek(CLOCK_LOW) < ms) {
    }
    return 0;
}

// ---- обёртки над диском, параметризованные diskId (0=C, 1=D) ----

int d_cmd(int diskId, int cmd) {
    if (diskId == 0) { poke(C_CMD, cmd); return 0; }
    poke(D_CMD, cmd);
    return 0;
}

int d_status(int diskId) {
    if (diskId == 0) { return peek(C_STATUS); }
    return peek(D_STATUS);
}

int d_data(int diskId) {
    if (diskId == 0) { return peek(C_DATA); }
    return peek(D_DATA);
}

int d_set_data(int diskId, int value) {
    if (diskId == 0) { poke(C_DATA, value); return 0; }
    poke(D_DATA, value);
    return 0;
}

int d_name_char(int diskId, int idx) {
    if (diskId == 0) { return diskCName[idx]; }
    return diskDName[idx];
}

int d_set_name_char(int diskId, int idx, int value) {
    if (diskId == 0) { diskCName[idx] = value; return 0; }
    diskDName[idx] = value;
    return 0;
}

// ---- листинг ----

int populate_left() {
    int i;
    int ch;
    int done;

    leftCount = 0;
    d_cmd(0, 1);   // LIST_FIRST

    done = 0;
    while (done == 0) {
        if (d_status(0) == 1) {
            done = 1;
        } else {
            leftIsDir[leftCount] = 0;
            i = 0;
            while (i < 12) {
                ch = d_name_char(0, i);
                leftNames[leftCount * 12 + i] = ch;
                if (ch == 47) { leftIsDir[leftCount] = 1; }   // '/'
                i = i + 1;
            }
            leftCount = leftCount + 1;
            if (leftCount < MAX_FILES) {
                d_cmd(0, 2);   // LIST_NEXT
            } else {
                done = 1;
            }
        }
    }
    if (leftSel >= leftCount) { leftSel = 0; }
    return 0;
}

int populate_right() {
    int i;
    int ch;
    int done;

    rightCount = 0;
    d_cmd(1, 1);   // LIST_FIRST

    done = 0;
    while (done == 0) {
        if (d_status(1) == 1) {
            done = 1;
        } else {
            rightIsDir[rightCount] = 0;
            i = 0;
            while (i < 12) {
                ch = d_name_char(1, i);
                rightNames[rightCount * 12 + i] = ch;
                if (ch == 47) { rightIsDir[rightCount] = 1; }
                i = i + 1;
            }
            rightCount = rightCount + 1;
            if (rightCount < MAX_FILES) {
                d_cmd(1, 2);   // LIST_NEXT
            } else {
                done = 1;
            }
        }
    }
    if (rightSel >= rightCount) { rightSel = 0; }
    return 0;
}

// ---- отрисовка ----

int draw_frame(int baseX, int width, int height, int headColor) {
    int x;
    int y;

    print_char(baseX, 0, 201);            // ╔
    set_color(baseX, 0, headColor, 0);
    print_char(baseX + width - 1, 0, 187); // ╗
    set_color(baseX + width - 1, 0, headColor, 0);

    x = baseX + 1;
    while (x < baseX + width - 1) {
        print_char(x, 0, 205);             // ═
        set_color(x, 0, headColor, 0);
        x = x + 1;
    }

    y = 1;
    while (y < height - 1) {
        print_char(baseX, y, 186);         // ║
        set_color(baseX, y, headColor, 0);
        print_char(baseX + width - 1, y, 186);
        set_color(baseX + width - 1, y, headColor, 0);
        y = y + 1;
    }

    print_char(baseX, height - 1, 200);    // ╚
    set_color(baseX, height - 1, headColor, 0);
    print_char(baseX + width - 1, height - 1, 188); // ╝
    set_color(baseX + width - 1, height - 1, headColor, 0);

    x = baseX + 1;
    while (x < baseX + width - 1) {
        print_char(x, height - 1, 205);
        set_color(x, height - 1, headColor, 0);
        x = x + 1;
    }

    return 0;
}

int render_left() {
    int i;
    int j;
    int y;
    int ch;
    int color;
    int headColor;

    headColor = COLOR_HEAD_INACTIVE;
    if (activeRight == 0) { headColor = COLOR_HEAD_ACTIVE; }

    draw_frame(0, 38, MAX_FILES + 2, headColor);
    print_str(2, 0, "C:");
    set_color(2, 0, headColor, 0);

    i = 0;
    while (i < MAX_FILES) {
        y = i + 1;
        j = 0;
        while (j < 12) {
            if (i < leftCount) {
                ch = leftNames[i * 12 + j];
                if (ch == 0) { ch = 32; }
            } else {
                ch = 32;
            }
            print_char(1 + j, y, ch);
            j = j + 1;
        }

        if (i < leftCount) {
            color = COLOR_FILE;
            if (leftIsDir[i] == 1) { color = COLOR_DIR; }
            if (i == leftSel) { color = COLOR_SEL; }
            j = 0;
            while (j < 12) {
                set_color(1 + j, y, color, 0);
                j = j + 1;
            }
        }

        i = i + 1;
    }

    return 0;
}

int render_right() {
    int i;
    int j;
    int y;
    int ch;
    int color;
    int headColor;
    int baseX;

    baseX = 40;
    headColor = COLOR_HEAD_INACTIVE;
    if (activeRight == 1) { headColor = COLOR_HEAD_ACTIVE; }

    draw_frame(baseX, 38, MAX_FILES + 2, headColor);
    print_str(baseX + 2, 0, "D:");
    set_color(baseX + 2, 0, headColor, 0);

    i = 0;
    while (i < MAX_FILES) {
        y = i + 1;
        j = 0;
        while (j < 12) {
            if (i < rightCount) {
                ch = rightNames[i * 12 + j];
                if (ch == 0) { ch = 32; }
            } else {
                ch = 32;
            }
            print_char(baseX + 1 + j, y, ch);
            j = j + 1;
        }

        if (i < rightCount) {
            color = COLOR_FILE;
            if (rightIsDir[i] == 1) { color = COLOR_DIR; }
            if (i == rightSel) { color = COLOR_SEL; }
            j = 0;
            while (j < 12) {
                set_color(baseX + 1 + j, y, color, 0);
                j = j + 1;
            }
        }

        i = i + 1;
    }

    return 0;
}

int render_status() {
    // Подсказка в стиле Norton Commander - реально работает пока
    // только F5 (Copy), остальные - только подписи (см. комментарий
    // в начале файла). Чёрный текст на белом фоне на всю ширину
    // строки - классическая полоса подсказок NC.
    int x;

    print_str(0, MAX_FILES + 2, "Tab-panel  W/S-move  Enter-dir  Backspace-up  Ctrl+Q-exit");

    print_str(0, MAX_FILES + 3, "F1Help F2Menu F3View F4Edit F5Copy F6Move F7MkDir F8Del F9PgDn F10Quit");
    x = 0;
    while (x < 80) {
        set_color(x, MAX_FILES + 3, 0, 7);
        x = x + 1;
    }

    return 0;
}

// ---- действия ----

int move_up() {
    if (activeRight == 0) {
        if (leftSel > 0) {
            leftSel = leftSel - 1;
            render_left();
        }
    } else {
        if (rightSel > 0) {
            rightSel = rightSel - 1;
            render_right();
        }
    }
    return 0;
}

int move_down() {
    if (activeRight == 0) {
        if (leftSel < leftCount - 1) {
            leftSel = leftSel + 1;
            render_left();
        }
    } else {
        if (rightSel < rightCount - 1) {
            rightSel = rightSel + 1;
            render_right();
        }
    }
    return 0;
}

int switch_panel() {
    if (activeRight == 0) { activeRight = 1; } else { activeRight = 0; }
    render_left();
    render_right();
    return 0;
}

int enter_dir() {
    int diskId;
    int sel;
    int isDir;
    int i;
    int ch;

    if (activeRight == 0) { diskId = 0; sel = leftSel; } else { diskId = 1; sel = rightSel; }

    if (activeRight == 0) {
        if (leftCount == 0) { return 0; }
        isDir = leftIsDir[sel];
    } else {
        if (rightCount == 0) { return 0; }
        isDir = rightIsDir[sel];
    }
    if (isDir == 0) { return 0; }

    i = 0;
    while (i < 12) {
        if (activeRight == 0) { ch = leftNames[sel * 12 + i]; } else { ch = rightNames[sel * 12 + i]; }
        if (ch == 47) { ch = 0; }   // обрезать хвостовой '/'
        d_set_name_char(diskId, i, ch);
        i = i + 1;
    }

    d_cmd(diskId, 11);   // CHDIR
    if (d_status(diskId) == 0) {
        if (activeRight == 0) {
            populate_left();
            leftSel = 0;
            render_left();
        } else {
            populate_right();
            rightSel = 0;
            render_right();
        }
    }
    return 0;
}

int go_up_dir() {
    int diskId;
    if (activeRight == 0) { diskId = 0; } else { diskId = 1; }

    d_cmd(diskId, 12);   // CHDIR_UP - в корне тихо ничего не делает

    if (activeRight == 0) {
        populate_left();
        leftSel = 0;
        render_left();
    } else {
        populate_right();
        rightSel = 0;
        render_right();
    }
    return 0;
}

int do_copy() {
    int srcDisk;
    int dstDisk;
    int sel;
    int isDir;
    int i;
    int ch;
    int done;

    if (activeRight == 0) { srcDisk = 0; dstDisk = 1; sel = leftSel; } else { srcDisk = 1; dstDisk = 0; sel = rightSel; }

    if (activeRight == 0) {
        if (leftCount == 0) { return 0; }
        isDir = leftIsDir[sel];
    } else {
        if (rightCount == 0) { return 0; }
        isDir = rightIsDir[sel];
    }
    if (isDir == 1) { return 0; }   // папки не копируем в v1

    i = 0;
    while (i < 12) {
        if (activeRight == 0) { ch = leftNames[sel * 12 + i]; } else { ch = rightNames[sel * 12 + i]; }
        d_set_name_char(srcDisk, i, ch);
        d_set_name_char(dstDisk, i, ch);
        i = i + 1;
    }

    d_cmd(srcDisk, 3);   // OPEN_READ
    if (d_status(srcDisk) == 2) { return 0; }   // источник не найден

    d_cmd(dstDisk, 5);   // OPEN_WRITE

    done = 0;
    while (done == 0) {
        d_cmd(srcDisk, 4);   // READ_BYTE
        if (d_status(srcDisk) == 1) {
            done = 1;
        } else {
            ch = d_data(srcDisk);
            d_set_data(dstDisk, ch);
            d_cmd(dstDisk, 6);   // WRITE_BYTE
        }
    }

    d_cmd(srcDisk, 7);   // CLOSE
    d_cmd(dstDisk, 7);

    if (dstDisk == 0) {
        populate_left();
        render_left();
    } else {
        populate_right();
        render_right();
    }

    return 0;
}

int main() {
    int key;
    int running;

    clear_screen();

    leftSel = 0;
    rightSel = 0;
    activeRight = 0;

    populate_left();
    populate_right();

    render_left();
    render_right();
    render_status();

    running = 1;
    while (running == 1) {
        key = peek(KEY_DATA);

        if (key == 17) { running = 0; }   // Ctrl+Q

        if (key == 9) { switch_panel(); }   // Tab

        if (key == 119) { move_up(); }      // w
        if (key == 87)  { move_up(); }
        if (key == 115) { move_down(); }    // s
        if (key == 83)  { move_down(); }

        if (key == 13) { enter_dir(); }     // Enter
        if (key == 8)  { go_up_dir(); }     // Backspace

        if (key == FKEY_F5) { do_copy(); }   // F5

        wait_ms(80);
    }

    clear_screen();

    return 0;
}
