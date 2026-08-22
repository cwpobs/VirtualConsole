// FM.MC - двухпанельный файловый менеджер (аналог Norton Commander)
// на мини-C (см. ASSEMBLY.md, "Мини-C"). Диск для каждой панели
// выбирается независимо (Alt+F1/Alt+F2, см. ниже) - в том числе обе
// панели могут смотреть на ОДИН И ТОТ ЖЕ физический диск, но разные
// папки (например, чтобы копировать файлы между папками одного
// диска). Технически у каждого Disk (см. Disk.cpp) ровно одно поле
// currentDir - если бы две панели одновременно "смотрели" на один
// диск без дополнительных мер, навигация в одной панели сбивала бы
// позицию другой. Решение: каждая панель хранит СВОЙ путь как стек
// имён папок от корня (leftPathNames/rightPathNames), и перед любым
// обращением к диску восстанавливает нужный currentDir - поднимается
// в корень (CHDIR_UP, безопасный no-op в корне) и спускается заново
// через CHDIR по своим сохранённым именам (см. sync_disk_to_panel).
// diskOwnerPanel[] помнит, чей путь сейчас актуален на каждом
// физическом диске, чтобы не пересинхронизировать лишний раз.
//
// Работает с диском НАПРЯМУЮ через poke/peek теми же MMIO-регистрами,
// что уже использует cmd_dir/cmd_copy в SHELL.ASM (LIST_FIRST/
// LIST_NEXT/CHDIR/CHDIR_UP/OPEN_READ/READ_BYTE/OPEN_WRITE/WRITE_BYTE/
// CLOSE) - SHELL.ASM не тронут вообще, это отдельная программа.
//
// Управление: Tab - переключить панель, стрелки Вверх/Вниз - по
// списку, Enter - зайти в папку, Backspace - подняться на уровень
// выше, Alt+F1/Alt+F2 - сменить диск левой/правой панели, Ctrl+Q -
// выход. Внизу экрана - подсказка F1-F10 в стиле Norton Commander -
// реально работает пока только F5 (Copy), остальные - только подписи
// (v1, задел на будущее: F3 View, F4 Edit, F6 Move, F7 MkDir, F8 Del
// и т.д.).
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
const KEY_UP = 72;    // стрелка вверх (extended-код _getch())
const KEY_DOWN = 80;  // стрелка вниз
const ALT_F1 = 104;   // сменить диск левой панели
const ALT_F2 = 105;   // сменить диск правой панели

const MAX_PATH_DEPTH = 8;
const NONE_PANEL = 2;   // сентинел diskOwnerPanel - "ещё никто" (в мини-C нет отрицательных литералов)

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
int leftDisk;               // 0 = C, 1 = D
int leftPathDepth;
int leftPathNames[96];      // MAX_PATH_DEPTH(8) * 12

int rightNames[216];
int rightIsDir[18];
int rightCount;
int rightSel;
int rightDisk;               // 0 = C, 1 = D
int rightPathDepth;
int rightPathNames[96];      // MAX_PATH_DEPTH(8) * 12

int diskOwnerPanel[2];   // индекс - diskId (0=C,1=D), значение - чей путь сейчас на диске (0=left,1=right,NONE_PANEL=никто)

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

// ---- синхронизация currentDir физического диска под нужную панель ----

int sync_disk_to_panel(int panel) {
    int diskId;
    int depth;
    int i;
    int j;
    int ch;

    if (panel == 0) { diskId = leftDisk; } else { diskId = rightDisk; }

    if (diskOwnerPanel[diskId] == panel) { return 0; }   // уже туда смотрит

    i = 0;
    while (i < MAX_PATH_DEPTH) {
        d_cmd(diskId, 12);   // CHDIR_UP - в корне безопасный no-op
        i = i + 1;
    }

    if (panel == 0) { depth = leftPathDepth; } else { depth = rightPathDepth; }

    i = 0;
    while (i < depth) {
        j = 0;
        while (j < 12) {
            if (panel == 0) { ch = leftPathNames[i * 12 + j]; } else { ch = rightPathNames[i * 12 + j]; }
            d_set_name_char(diskId, j, ch);
            j = j + 1;
        }
        d_cmd(diskId, 11);   // CHDIR
        i = i + 1;
    }

    diskOwnerPanel[diskId] = panel;
    return 0;
}

// ---- листинг ----

int populate_left() {
    int i;
    int ch;
    int done;

    sync_disk_to_panel(0);

    leftCount = 0;
    d_cmd(leftDisk, 1);   // LIST_FIRST

    done = 0;
    while (done == 0) {
        if (d_status(leftDisk) == 1) {
            done = 1;
        } else {
            leftIsDir[leftCount] = 0;
            i = 0;
            while (i < 12) {
                ch = d_name_char(leftDisk, i);
                leftNames[leftCount * 12 + i] = ch;
                if (ch == 47) { leftIsDir[leftCount] = 1; }   // '/'
                i = i + 1;
            }
            leftCount = leftCount + 1;
            if (leftCount < MAX_FILES) {
                d_cmd(leftDisk, 2);   // LIST_NEXT
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

    sync_disk_to_panel(1);

    rightCount = 0;
    d_cmd(rightDisk, 1);   // LIST_FIRST

    done = 0;
    while (done == 0) {
        if (d_status(rightDisk) == 1) {
            done = 1;
        } else {
            rightIsDir[rightCount] = 0;
            i = 0;
            while (i < 12) {
                ch = d_name_char(rightDisk, i);
                rightNames[rightCount * 12 + i] = ch;
                if (ch == 47) { rightIsDir[rightCount] = 1; }
                i = i + 1;
            }
            rightCount = rightCount + 1;
            if (rightCount < MAX_FILES) {
                d_cmd(rightDisk, 2);   // LIST_NEXT
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
    if (leftDisk == 0) { print_char(2, 0, 67); } else { print_char(2, 0, 68); }   // 'C'/'D'
    print_char(3, 0, 58);   // ':'
    set_color(2, 0, headColor, 0);
    set_color(3, 0, headColor, 0);

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
    if (rightDisk == 0) { print_char(baseX + 2, 0, 67); } else { print_char(baseX + 2, 0, 68); }   // 'C'/'D'
    print_char(baseX + 3, 0, 58);   // ':'
    set_color(baseX + 2, 0, headColor, 0);
    set_color(baseX + 3, 0, headColor, 0);

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

    print_str(0, MAX_FILES + 2, "Tab-panel  ^/v-move  Enter-dir  Backspace-up  Alt+F1/F2-drive  Ctrl+Q-exit");

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

int select_disk_left() {
    if (leftDisk == 0) { leftDisk = 1; } else { leftDisk = 0; }
    leftPathDepth = 0;
    leftSel = 0;
    populate_left();
    render_left();
    return 0;
}

int select_disk_right() {
    if (rightDisk == 0) { rightDisk = 1; } else { rightDisk = 0; }
    rightPathDepth = 0;
    rightSel = 0;
    populate_right();
    render_right();
    return 0;
}

int enter_dir() {
    int diskId;
    int sel;
    int isDir;
    int i;
    int ch;
    int depth;

    if (activeRight == 0) { diskId = leftDisk; sel = leftSel; } else { diskId = rightDisk; sel = rightSel; }

    if (activeRight == 0) {
        if (leftCount == 0) { return 0; }
        isDir = leftIsDir[sel];
        depth = leftPathDepth;
    } else {
        if (rightCount == 0) { return 0; }
        isDir = rightIsDir[sel];
        depth = rightPathDepth;
    }
    if (isDir == 0) { return 0; }
    if (depth >= MAX_PATH_DEPTH) { return 0; }   // дальше вглубь не пускаем

    sync_disk_to_panel(activeRight);

    i = 0;
    while (i < 12) {
        if (activeRight == 0) { ch = leftNames[sel * 12 + i]; } else { ch = rightNames[sel * 12 + i]; }
        if (ch == 47) { ch = 0; }   // обрезать хвостовой '/'
        d_set_name_char(diskId, i, ch);
        if (activeRight == 0) { leftPathNames[depth * 12 + i] = ch; } else { rightPathNames[depth * 12 + i] = ch; }
        i = i + 1;
    }

    d_cmd(diskId, 11);   // CHDIR
    if (d_status(diskId) == 0) {
        if (activeRight == 0) {
            leftPathDepth = depth + 1;
            populate_left();
            leftSel = 0;
            render_left();
        } else {
            rightPathDepth = depth + 1;
            populate_right();
            rightSel = 0;
            render_right();
        }
    }
    return 0;
}

int go_up_dir() {
    int diskId;
    if (activeRight == 0) { diskId = leftDisk; } else { diskId = rightDisk; }

    sync_disk_to_panel(activeRight);
    d_cmd(diskId, 12);   // CHDIR_UP - в корне тихо ничего не делает

    if (activeRight == 0) {
        if (leftPathDepth > 0) { leftPathDepth = leftPathDepth - 1; }
        populate_left();
        leftSel = 0;
        render_left();
    } else {
        if (rightPathDepth > 0) { rightPathDepth = rightPathDepth - 1; }
        populate_right();
        rightSel = 0;
        render_right();
    }
    return 0;
}

int do_copy() {
    int srcPanel;
    int dstPanel;
    int srcDisk;
    int dstDisk;
    int sel;
    int isDir;
    int i;
    int ch;
    int done;
    int sameFile;
    int a;

    if (activeRight == 0) { srcPanel = 0; dstPanel = 1; sel = leftSel; } else { srcPanel = 1; dstPanel = 0; sel = rightSel; }
    srcDisk = leftDisk; if (srcPanel == 1) { srcDisk = rightDisk; }
    dstDisk = leftDisk; if (dstPanel == 1) { dstDisk = rightDisk; }

    if (activeRight == 0) {
        if (leftCount == 0) { return 0; }
        isDir = leftIsDir[sel];
    } else {
        if (rightCount == 0) { return 0; }
        isDir = rightIsDir[sel];
    }
    if (isDir == 1) { return 0; }   // папки не копируем в v1

    // Отказ копировать файл сам в себя (тот же физический диск, та же
    // папка) - иначе OPEN_WRITE (trunc) на приёмнике испортит ещё не
    // дочитанный источник (см. план - readStream/writeStream общего
    // Disk-объекта независимы, но целятся в один и тот же файл на диске).
    sameFile = 0;
    if (srcDisk == dstDisk) {
        if (leftPathDepth == rightPathDepth) {
            sameFile = 1;
            i = 0;
            while (i < leftPathDepth) {
                a = 0;
                while (a < 12) {
                    if (leftPathNames[i * 12 + a] != rightPathNames[i * 12 + a]) { sameFile = 0; }
                    a = a + 1;
                }
                i = i + 1;
            }
        }
    }
    if (sameFile == 1) { return 0; }

    sync_disk_to_panel(srcPanel);
    i = 0;
    while (i < 12) {
        if (activeRight == 0) { ch = leftNames[sel * 12 + i]; } else { ch = rightNames[sel * 12 + i]; }
        d_set_name_char(srcDisk, i, ch);
        i = i + 1;
    }

    d_cmd(srcDisk, 3);   // OPEN_READ
    if (d_status(srcDisk) == 2) { return 0; }   // источник не найден

    sync_disk_to_panel(dstPanel);
    i = 0;
    while (i < 12) {
        if (activeRight == 0) { ch = leftNames[sel * 12 + i]; } else { ch = rightNames[sel * 12 + i]; }
        d_set_name_char(dstDisk, i, ch);
        i = i + 1;
    }
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

    if (dstPanel == 0) {
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

    leftDisk = 0;
    rightDisk = 1;
    leftPathDepth = 0;
    rightPathDepth = 0;
    diskOwnerPanel[0] = NONE_PANEL;
    diskOwnerPanel[1] = NONE_PANEL;

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

        if (key == KEY_UP)   { move_up(); }
        if (key == KEY_DOWN) { move_down(); }

        if (key == 13) { enter_dir(); }     // Enter
        if (key == 8)  { go_up_dir(); }     // Backspace

        if (key == FKEY_F5) { do_copy(); }   // F5

        if (key == ALT_F1) { select_disk_left(); }
        if (key == ALT_F2) { select_disk_right(); }

        wait_ms(80);
    }

    clear_screen();

    return 0;
}
