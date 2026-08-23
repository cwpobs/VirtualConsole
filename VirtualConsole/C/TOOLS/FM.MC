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
// списку, Enter - зайти в папку ИЛИ запустить выбранный *.RUN (см.
// exec_child() ниже), Backspace - подняться на уровень выше,
// Alt+F1/Alt+F2 - сменить диск левой/правой панели, Ctrl+Q - выход.
// Внизу экрана - подсказка F1-F10 в стиле Norton Commander - реально
// работают F2 (Rename - см. request_rename()/perform_rename(),
// переименовывает выделенный файл/папку по введённому имени,
// предзаполненному текущим), F3 (View - см. view_selected_file(),
// открывает выделенный файл в C/TOOLS/VIEW.MC), F4 (Edit - см.
// edit_selected_file(), открывает выделенный файл в C/TOOLS/EDIT.MC -
// полноэкранный редактор текста, весь файл в памяти, сохранение по
// Ctrl+S), F5 (Copy), F6 (Move - см. do_move(), тот же перенос байт,
// что F5, плюс удаление источника), F7 (MkDir - см. request_mkdir(),
// создаёт папку в текущей папке активной панели по введённому имени),
// F8 (Del - см. request_delete(), удаляет выделенный файл/ПУСТУЮ папку
// после подтверждения Y/N) и F10 (Build - см. build_selected_file(),
// собирает выделенный *.ASM/*.MC через BUILD в Disk), остальные -
// только подписи (v1, задел на будущее). Наверху
// списка появляется пункт ".." (если панель
// не в корне диска, см. populate_left()/populate_right()) - Enter на
// нём поднимает на уровень вверх (как Backspace), удалить/перенести/
// скопировать его нельзя (см. is_dotdot_selected()).
//
// Запуск *.RUN (run_program()) - через системный вызов SHELL.ASM
// (shell_exec_child, см. ASSEMBLY.md/exec_child) - FM.MC только кладёт
// NAME на нужный диск и говорит shell'у, какой это диск
// (EXEC_CHILD_DISK), сам выбор адреса песочницы и учёт вложенности -
// целиком на стороне shell'а. После возврата дочерней программы (её
// main() дойдёт до RET) - полная перерисовка экрана, который она
// наверняка использовала под себя.
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

const FKEY_F2 = 60;   // Rename
const FKEY_F3 = 61;   // View
const FKEY_F4 = 62;   // Edit
const FKEY_F5 = 63;   // Copy
const FKEY_F6 = 64;   // Move
const FKEY_F7 = 65;   // MkDir
const FKEY_F8 = 66;   // Del
const FKEY_F10 = 68;  // Build
const KEY_UP = 72;    // стрелка вверх (extended-код _getch())
const KEY_DOWN = 80;  // стрелка вниз
const ALT_F1 = 104;   // сменить диск левой панели
const ALT_F2 = 105;   // сменить диск правой панели

const MAX_PATH_DEPTH = 8;
const NONE_PANEL = 2;   // сентинел diskOwnerPanel - "ещё никто" (в мини-C нет отрицательных литералов)

const EXEC_CHILD_DISK = 0x0000000F;   // диск (0=C,1=D) с NAME запускаемой программы - читает shell_exec_child (см. exec_child())

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

// ---- подтверждение удаления (F8, см. request_delete()/perform_delete()) ----
int confirmPending;   // 0 = нет диалога, 1 = ждём Y/N/Enter/Esc
int delPanel;
int delDiskId;
int delSel;
int delName[12];

// ---- ввод текста - общий диалог для F7 (создать папку) и F2
// (переименовать), см. request_mkdir()/perform_mkdir()/
// request_rename()/perform_rename() ----
int inputPending;   // 0 = нет диалога, 1 = ждём ввод имени (печатаемые символы/Backspace/Enter/Esc)
int inputMode;       // 0 = mkdir (F7), 1 = rename (F2) - что делать по Enter
int mkdirName[12];   // текст поля ввода - и НОВОЕ имя папки, и НОВОЕ имя при переименовании
int mkdirLen;

// ---- переименование (F2, см. request_rename()/perform_rename()) ----
int renamePanel;
int renameDiskId;
int renameSel;
int renameOldName[12];   // имя ДО переименования - mkdirName тем временем держит НОВОЕ

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
    if (leftPathDepth > 0) {
        // Синтетический пункт ".." - не настоящий файл LIST_FIRST/NEXT,
        // просто маркер "подняться на уровень выше" (см. enter_dir()) -
        // отображается как обычная папка, но is_dotdot_selected()
        // защищает его от удаления/переноса/просмотра.
        leftIsDir[0] = 1;
        leftNames[0] = 46;   // '.'
        leftNames[1] = 46;   // '.'
        i = 2;
        while (i < 12) { leftNames[i] = 0; i = i + 1; }
        leftCount = 1;
    }

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
    if (rightPathDepth > 0) {
        // См. populate_left() - тот же синтетический пункт "..".
        rightIsDir[0] = 1;
        rightNames[0] = 46;   // '.'
        rightNames[1] = 46;   // '.'
        i = 2;
        while (i < 12) { rightNames[i] = 0; i = i + 1; }
        rightCount = 1;
    }

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
    // Подсказка в стиле Norton Commander - реально работают F3 (View),
    // F5 (Copy), F6 (Move), F7 (MkDir), F8 (Del) и F10 (Build),
    // остальные - только подписи (см. комментарий в начале файла).
    // Чёрный текст на белом фоне на всю ширину строки - классическая
    // полоса подсказок NC.
    int x;

    print_str(0, MAX_FILES + 2, "Tab-panel  ^/v-move  Enter-dir  Backspace-up  Alt+F1/F2-drive  Ctrl+Q-exit");

    print_str(0, MAX_FILES + 3, "F1Help F2Rename F3View F4Edit F5Copy F6Move F7MkDir F8Del F9PgDn F10Build");
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

// ---- пункт ".." (см. populate_left/populate_right) ----

int is_dotdot_selected(int panel, int sel) {
    int depth;
    if (sel != 0) { return 0; }
    if (panel == 0) { depth = leftPathDepth; } else { depth = rightPathDepth; }
    if (depth > 0) { return 1; }
    return 0;
}

// ---- запуск *.RUN ----

int is_run_file(int panel, int sel) {
    // Ищет длину имени (до первого 0 в 12-байтовом NAME) и сравнивает
    // последние 4 символа с ".RUN" (46,82,85,78).
    int len;
    int done;
    int ch;
    int c1;
    int c2;
    int c3;
    int c4;

    len = 0;
    done = 0;
    while (done == 0) {
        if (panel == 0) { ch = leftNames[sel * 12 + len]; } else { ch = rightNames[sel * 12 + len]; }
        if (ch == 0) {
            done = 1;
        } else {
            len = len + 1;
            if (len >= 12) { done = 1; }
        }
    }

    if (len < 4) { return 0; }

    if (panel == 0) {
        c1 = leftNames[sel * 12 + len - 4];
        c2 = leftNames[sel * 12 + len - 3];
        c3 = leftNames[sel * 12 + len - 2];
        c4 = leftNames[sel * 12 + len - 1];
    } else {
        c1 = rightNames[sel * 12 + len - 4];
        c2 = rightNames[sel * 12 + len - 3];
        c3 = rightNames[sel * 12 + len - 2];
        c4 = rightNames[sel * 12 + len - 1];
    }

    if (c1 != 46) { return 0; }   // '.'
    if (c2 != 82) { return 0; }   // 'R'
    if (c3 != 85) { return 0; }   // 'U'
    if (c4 != 78) { return 0; }   // 'N'
    return 1;
}

// ---- сборка *.ASM/*.MC (F10) ----

int is_buildable_file(int panel, int sel) {
    // Тот же приём, что is_run_file() выше, но проверяет ".ASM" (4
    // символа) ИЛИ ".MC" (3 символа) - оба расширения Disk::build()
    // уже различает сам (см. ASSEMBLY.md, "Disk", BUILD). Каталоги
    // (имя оканчивается на '/', 47) ни под одно из них не подходят -
    // отдельной проверки isDir не нужно.
    int len;
    int done;
    int ch;
    int c1;
    int c2;
    int c3;
    int c4;

    len = 0;
    done = 0;
    while (done == 0) {
        if (panel == 0) { ch = leftNames[sel * 12 + len]; } else { ch = rightNames[sel * 12 + len]; }
        if (ch == 0) {
            done = 1;
        } else {
            len = len + 1;
            if (len >= 12) { done = 1; }
        }
    }

    if (len >= 4) {
        if (panel == 0) {
            c1 = leftNames[sel * 12 + len - 4];
            c2 = leftNames[sel * 12 + len - 3];
            c3 = leftNames[sel * 12 + len - 2];
            c4 = leftNames[sel * 12 + len - 1];
        } else {
            c1 = rightNames[sel * 12 + len - 4];
            c2 = rightNames[sel * 12 + len - 3];
            c3 = rightNames[sel * 12 + len - 2];
            c4 = rightNames[sel * 12 + len - 1];
        }
        if (c1 == 46) {                    // '.'
            if (c2 == 65) {                // 'A'
                if (c3 == 83) {            // 'S'
                    if (c4 == 77) { return 1; }   // 'M'
                }
            }
        }
    }

    if (len >= 3) {
        if (panel == 0) {
            c2 = leftNames[sel * 12 + len - 3];
            c3 = leftNames[sel * 12 + len - 2];
            c4 = leftNames[sel * 12 + len - 1];
        } else {
            c2 = rightNames[sel * 12 + len - 3];
            c3 = rightNames[sel * 12 + len - 2];
            c4 = rightNames[sel * 12 + len - 1];
        }
        if (c2 == 46) {                // '.'
            if (c3 == 77) {            // 'M'
                if (c4 == 67) { return 1; }   // 'C'
            }
        }
    }

    return 0;
}

int build_selected_file() {
    // F10 - собирает выделенный *.ASM/*.MC через BUILD (14 в Disk) -
    // в отличие от run_program()/view_selected_file(), не запускает
    // ничего (не exec_child, обычная команда устройства) - просто
    // кладёт NAME на диск панели и ждёт результата синхронно, как
    // "build ИМЯ" в шелле (см. ASSEMBLY.md, "Disk"). Тихо ничего не
    // делает при ошибке компиляции/сборки - как и сам шелл, отдельного
    // сообщения об ошибке не показывает.
    int panel;
    int diskId;
    int sel;
    int i;
    int ch;

    panel = activeRight;
    if (panel == 0) { diskId = leftDisk; sel = leftSel; } else { diskId = rightDisk; sel = rightSel; }

    if (panel == 0) { if (leftCount == 0) { return 0; } } else { if (rightCount == 0) { return 0; } }
    if (is_buildable_file(panel, sel) == 0) { return 0; }

    sync_disk_to_panel(panel);

    i = 0;
    while (i < 12) {
        if (panel == 0) { ch = leftNames[sel * 12 + i]; } else { ch = rightNames[sel * 12 + i]; }
        d_set_name_char(diskId, i, ch);
        i = i + 1;
    }

    d_cmd(diskId, 14);   // BUILD

    // Новый ИМЯ.RUN появился рядом с исходником - обновить список.
    if (panel == 0) { populate_left(); render_left(); } else { populate_right(); render_right(); }

    return 0;
}

// ---- удаление файла/пустой папки (F8, как в Norton Commander) ----
//
// Двухшаговое подтверждение: F8 запоминает, ЧТО удалять
// (request_delete()), и включает confirmPending - пока он включён,
// main() игнорирует все обычные клавиши и ждёт только Y/N/Enter/Esc
// (см. main()). Disk::deleteFile() (DELETE=9) сам по себе уже отличает
// файл от НЕПУСТОЙ папки (std::filesystem::remove просто отказывает,
// STATUS=2) - здесь это никак отдельно не проверяется, тихий отказ
// (папка останется в списке) - тот же стиль, что уже принят для
// build_selected_file()/шелловского "build".

const DELCONF_X = 20;
const DELCONF_Y = 9;
const DELCONF_W = 40;
const DELCONF_H = 5;

int draw_confirm_box() {
    int x;
    int y;
    int i;
    int ch;

    print_char(DELCONF_X, DELCONF_Y, 201);                      // ╔
    print_char(DELCONF_X + DELCONF_W - 1, DELCONF_Y, 187);       // ╗
    x = DELCONF_X + 1;
    while (x < DELCONF_X + DELCONF_W - 1) { print_char(x, DELCONF_Y, 205); x = x + 1; }

    y = DELCONF_Y + 1;
    while (y < DELCONF_Y + DELCONF_H - 1) {
        print_char(DELCONF_X, y, 186);                           // ║
        print_char(DELCONF_X + DELCONF_W - 1, y, 186);
        x = DELCONF_X + 1;
        while (x < DELCONF_X + DELCONF_W - 1) { print_char(x, y, 32); x = x + 1; }
        y = y + 1;
    }

    print_char(DELCONF_X, DELCONF_Y + DELCONF_H - 1, 200);       // ╚
    print_char(DELCONF_X + DELCONF_W - 1, DELCONF_Y + DELCONF_H - 1, 188); // ╝
    x = DELCONF_X + 1;
    while (x < DELCONF_X + DELCONF_W - 1) { print_char(x, DELCONF_Y + DELCONF_H - 1, 205); x = x + 1; }

    // жёлтый текст на синем - классический модальный диалог NC
    y = DELCONF_Y;
    while (y < DELCONF_Y + DELCONF_H) {
        x = DELCONF_X;
        while (x < DELCONF_X + DELCONF_W) { set_color(x, y, 14, 1); x = x + 1; }
        y = y + 1;
    }

    print_str(DELCONF_X + 2, DELCONF_Y + 1, "Delete");
    i = 0;
    while (i < 12) {
        ch = delName[i];
        if (ch == 0) { ch = 32; }
        print_char(DELCONF_X + 9 + i, DELCONF_Y + 1, ch);
        i = i + 1;
    }
    print_char(DELCONF_X + 21, DELCONF_Y + 1, 63);   // '?'

    print_str(DELCONF_X + 2, DELCONF_Y + 3, "Y - yes    N/Esc - cancel");

    return 0;
}

int request_delete() {
    int panel;
    int sel;
    int i;

    panel = activeRight;
    if (panel == 0) { if (leftCount == 0) { return 0; } sel = leftSel; }
    else { if (rightCount == 0) { return 0; } sel = rightSel; }

    if (is_dotdot_selected(panel, sel) == 1) { return 0; }   // ".." нельзя удалить

    delPanel = panel;
    if (panel == 0) { delDiskId = leftDisk; } else { delDiskId = rightDisk; }
    delSel = sel;

    i = 0;
    while (i < 12) {
        if (panel == 0) { delName[i] = leftNames[sel * 12 + i]; } else { delName[i] = rightNames[sel * 12 + i]; }
        i = i + 1;
    }

    confirmPending = 1;
    draw_confirm_box();

    return 0;
}

int perform_delete() {
    int i;
    int ch;

    sync_disk_to_panel(delPanel);

    i = 0;
    while (i < 12) {
        ch = delName[i];
        if (ch == 47) { ch = 0; }   // обрезать хвостовой '/' у папок - см. enter_dir()
        d_set_name_char(delDiskId, i, ch);
        i = i + 1;
    }

    d_cmd(delDiskId, 9);   // DELETE

    if (delPanel == 0) { populate_left(); } else { populate_right(); }

    redraw_panels();

    return 0;
}

int redraw_panels() {
    // Полная перерисовка обеих панелей - снимает с экрана любое
    // модальное окошко (подтверждение удаления/ввод имени папки) и
    // приводит вид в порядок после него. Общая для отмены (Esc/N) в
    // обоих диалогах - см. main().
    clear_screen();
    render_left();
    render_right();
    render_status();

    return 0;
}

// ---- создание папки (F7, как в Norton Commander) ----
//
// В отличие от F8 (Y/N-подтверждение) - тут настоящий ввод текста:
// печатаемые символы копятся в mkdirName/mkdirLen по одному за кадр,
// пока inputPending==1 - main() в этом режиме тоже игнорирует все
// обычные клавиши (см. main()). Использует то же окошко (координаты
// DELCONF_X/Y/W/H), что и диалог удаления - они никогда не показаны
// одновременно.

int draw_input_frame() {
    // Общая рамка+фон для любого диалога ввода текста (F7/F2) - сама
    // надпись-заголовок и введённый текст рисует вызывающий код после
    // (print_str умеет только строковый ЛИТЕРАЛ, не переменную - общий
    // текст между F7/F2 не вынести, поэтому общая только рамка).
    int x;
    int y;

    print_char(DELCONF_X, DELCONF_Y, 201);                      // ╔
    print_char(DELCONF_X + DELCONF_W - 1, DELCONF_Y, 187);       // ╗
    x = DELCONF_X + 1;
    while (x < DELCONF_X + DELCONF_W - 1) { print_char(x, DELCONF_Y, 205); x = x + 1; }

    y = DELCONF_Y + 1;
    while (y < DELCONF_Y + DELCONF_H - 1) {
        print_char(DELCONF_X, y, 186);                           // ║
        print_char(DELCONF_X + DELCONF_W - 1, y, 186);
        x = DELCONF_X + 1;
        while (x < DELCONF_X + DELCONF_W - 1) { print_char(x, y, 32); x = x + 1; }
        y = y + 1;
    }

    print_char(DELCONF_X, DELCONF_Y + DELCONF_H - 1, 200);       // ╚
    print_char(DELCONF_X + DELCONF_W - 1, DELCONF_Y + DELCONF_H - 1, 188); // ╝
    x = DELCONF_X + 1;
    while (x < DELCONF_X + DELCONF_W - 1) { print_char(x, DELCONF_Y + DELCONF_H - 1, 205); x = x + 1; }

    // жёлтый текст на синем - тот же стиль, что и окошко удаления
    y = DELCONF_Y;
    while (y < DELCONF_Y + DELCONF_H) {
        x = DELCONF_X;
        while (x < DELCONF_X + DELCONF_W) { set_color(x, y, 14, 1); x = x + 1; }
        y = y + 1;
    }

    return 0;
}

int draw_input_text() {
    // Печатает текущий mkdirName/mkdirLen + курсор - общая часть для
    // draw_mkdir_box()/draw_rename_box(), вызывается ПОСЛЕ заголовка.
    int i;
    int ch;

    i = 0;
    while (i < 12) {
        if (i < mkdirLen) { ch = mkdirName[i]; } else { ch = 32; }
        print_char(DELCONF_X + 2 + i, DELCONF_Y + 3, ch);
        i = i + 1;
    }
    print_char(DELCONF_X + 2 + mkdirLen, DELCONF_Y + 3, 95);   // '_' - курсор сразу после введённого текста

    return 0;
}

int draw_mkdir_box() {
    draw_input_frame();
    print_str(DELCONF_X + 2, DELCONF_Y + 1, "New folder name:");
    draw_input_text();
    return 0;
}

int draw_rename_box() {
    draw_input_frame();
    print_str(DELCONF_X + 2, DELCONF_Y + 1, "Enter new name:");
    draw_input_text();
    return 0;
}

int request_mkdir() {
    int i;

    if (confirmPending == 1) { return 0; }   // диалог удаления уже открыт

    mkdirLen = 0;
    i = 0;
    while (i < 12) { mkdirName[i] = 0; i = i + 1; }   // хвост от предыдущего ввода не должен утечь в NAME

    inputMode = 0;
    inputPending = 1;
    draw_mkdir_box();

    return 0;
}

int request_rename() {
    int panel;
    int sel;
    int i;
    int len;
    int ch;
    int done;

    if (confirmPending == 1) { return 0; }   // диалог удаления уже открыт

    panel = activeRight;
    if (panel == 0) { if (leftCount == 0) { return 0; } sel = leftSel; }
    else { if (rightCount == 0) { return 0; } sel = rightSel; }

    if (is_dotdot_selected(panel, sel) == 1) { return 0; }   // ".." нельзя переименовать

    renamePanel = panel;
    if (panel == 0) { renameDiskId = leftDisk; } else { renameDiskId = rightDisk; }
    renameSel = sel;

    i = 0;
    while (i < 12) {
        if (panel == 0) { ch = leftNames[sel * 12 + i]; } else { ch = rightNames[sel * 12 + i]; }
        renameOldName[i] = ch;
        i = i + 1;
    }

    // Предзаполняем поле ввода текущим именем (без хвостового '/' у
    // папок, без нулевого хвоста) - как в Norton Commander, можно
    // просто подправить, а не перепечатывать заново.
    len = 0;
    done = 0;
    while (done == 0) {
        ch = renameOldName[len];
        if (ch == 0) { done = 1; } else { len = len + 1; if (len >= 12) { done = 1; } }
    }
    if (len > 0) {
        if (renameOldName[len - 1] == 47) { len = len - 1; }   // хвостовой '/' у папок
    }

    i = 0;
    while (i < 12) {
        if (i < len) { mkdirName[i] = renameOldName[i]; } else { mkdirName[i] = 0; }
        i = i + 1;
    }
    mkdirLen = len;

    inputMode = 1;
    inputPending = 1;
    draw_rename_box();

    return 0;
}

int perform_mkdir() {
    int diskId;
    int i;

    diskId = leftDisk;
    if (activeRight == 1) { diskId = rightDisk; }

    sync_disk_to_panel(activeRight);

    i = 0;
    while (i < 12) {
        d_set_name_char(diskId, i, mkdirName[i]);
        i = i + 1;
    }

    d_cmd(diskId, 19);   // MKDIR

    if (activeRight == 0) { populate_left(); } else { populate_right(); }

    redraw_panels();

    return 0;
}

int perform_rename() {
    // Две команды подряд (NAME не может держать два имени сразу, см.
    // шапку Disk.cpp) - REMEMBER_RENAME_FROM запоминает старое имя,
    // затем RENAME читает его и переименовывает в уже перезаписанный
    // NAME (новое имя из mkdirName).
    int i;
    int len;
    int done;
    int ch;

    sync_disk_to_panel(renamePanel);

    len = 0;
    done = 0;
    while (done == 0) {
        ch = renameOldName[len];
        if (ch == 0) { done = 1; } else { len = len + 1; if (len >= 12) { done = 1; } }
    }
    if (len > 0) {
        if (renameOldName[len - 1] == 47) { len = len - 1; }   // хвостовой '/' у папок
    }

    i = 0;
    while (i < 12) {
        if (i < len) { ch = renameOldName[i]; } else { ch = 0; }
        d_set_name_char(renameDiskId, i, ch);
        i = i + 1;
    }
    d_cmd(renameDiskId, 20);   // REMEMBER_RENAME_FROM

    i = 0;
    while (i < 12) {
        d_set_name_char(renameDiskId, i, mkdirName[i]);
        i = i + 1;
    }
    d_cmd(renameDiskId, 21);   // RENAME

    if (renamePanel == 0) { populate_left(); } else { populate_right(); }

    redraw_panels();

    return 0;
}

int run_program() {
    // Запускает выбранный *.RUN как дочернюю программу - см.
    // ASSEMBLY.md, "exec_child". Сама загрузка (какой командой диска,
    // по какому адресу) и учёт глубины вложенности теперь целиком на
    // стороне SHELL.ASM (shell_exec_child, системный вызов по
    // 0x0000000A) - FM.MC только кладёт NAME на нужный диск, говорит
    // shell'у, какой это диск (EXEC_CHILD_DISK), и зовёт exec_child().
    // Управление возвращается сюда же, когда дочерняя программа
    // завершится (её Mini-C main() дойдёт до RET) - или сразу же, если
    // shell не нашёл/не смог собрать файл (тихий отказ).
    int panel;
    int diskId;
    int sel;
    int i;
    int ch;

    panel = activeRight;
    if (panel == 0) { diskId = leftDisk; sel = leftSel; } else { diskId = rightDisk; sel = rightSel; }

    sync_disk_to_panel(panel);

    i = 0;
    while (i < 12) {
        if (panel == 0) { ch = leftNames[sel * 12 + i]; } else { ch = rightNames[sel * 12 + i]; }
        d_set_name_char(diskId, i, ch);
        i = i + 1;
    }

    poke(EXEC_CHILD_DISK, diskId);
    exec_child();

    // Дочерняя программа наверняка использовала экран под себя -
    // полная перерисовка; leftNames/rightNames и т.д. не тронуты,
    // заново их читать (populate_*) не нужно.
    clear_screen();
    render_left();
    render_right();
    render_status();

    return 0;
}

int view_selected_file() {
    // F3 - открывает выделенный файл в C/TOOLS/VIEW.MC (см. ASSEMBLY.md,
    // "Аргументы командной строки"). В отличие от run_program(), имя
    // ЗАПУСКАЕМОЙ программы (VIEW.RUN) и имя ПРОСМАТРИВАЕМОГО файла -
    // РАЗНЫЕ строки: NAME на диске держит "VIEW.RUN" (то, что грузит
    // shell_exec_child), а имя выбранного файла кладётся в cmdArgs -
    // отдельный канал, читает его VIEW.MC через peek(CMD_ARGS_LEN)/
    // cmdArgs (прелюдия компилятора - см. Compiler.cpp).
    //
    // VIEW.RUN ищется на ТОМ ЖЕ диске, что и просматриваемый файл
    // (diskId), но НЕ обязательно в той же папке, где сейчас currentDir
    // (FM.MC постоянно уводит его по панелям) - если LOAD_CHILD не
    // найдёт VIEW.RUN в текущей папке, Disk::loadChildRun() сам
    // подстрахуется резервным поиском там, откуда была запущена сама
    // FM.MC (Disk::lastExecDir), и только потом - в корне диска (см.
    // Disk.cpp) - поэтому достаточно собрать VIEW.RUN один раз, В ТОЙ
    // ЖЕ папке, что и сама FM.MC (обычно C/TOOLS) - никуда специально
    // копировать не нужно.
    int panel;
    int diskId;
    int sel;
    int i;
    int ch;

    panel = activeRight;
    if (panel == 0) { diskId = leftDisk; sel = leftSel; } else { diskId = rightDisk; sel = rightSel; }

    if (panel == 0) { if (leftCount == 0) { return 0; } } else { if (rightCount == 0) { return 0; } }
    if (panel == 0) { if (leftIsDir[sel] == 1) { return 0; } } else { if (rightIsDir[sel] == 1) { return 0; } }

    sync_disk_to_panel(panel);

    i = 0;
    while (i < 12) {
        if (panel == 0) { ch = leftNames[sel * 12 + i]; } else { ch = rightNames[sel * 12 + i]; }
        cmdArgs[i] = ch;
        i = i + 1;
    }
    poke(CMD_ARGS_LEN, 12);

    d_set_name_char(diskId, 0, 86);    // V
    d_set_name_char(diskId, 1, 73);    // I
    d_set_name_char(diskId, 2, 69);    // E
    d_set_name_char(diskId, 3, 87);    // W
    d_set_name_char(diskId, 4, 46);    // .
    d_set_name_char(diskId, 5, 82);    // R
    d_set_name_char(diskId, 6, 85);    // U
    d_set_name_char(diskId, 7, 78);    // N
    d_set_name_char(diskId, 8, 0);
    d_set_name_char(diskId, 9, 0);
    d_set_name_char(diskId, 10, 0);
    d_set_name_char(diskId, 11, 0);

    poke(EXEC_CHILD_DISK, diskId);
    exec_child();

    clear_screen();
    render_left();
    render_right();
    render_status();

    return 0;
}

int edit_selected_file() {
    // F4 - открывает выделенный файл в C/TOOLS/EDIT.MC (полноэкранный
    // редактор) - та же схема, что view_selected_file() выше (NAME на
    // диске держит "EDIT.RUN", имя редактируемого файла идёт через
    // cmdArgs), EDIT.RUN ищется тем же резервным механизмом
    // Disk::loadChildRun(), собирается один раз в той же папке, что и
    // сама FM.MC.
    int panel;
    int diskId;
    int sel;
    int i;
    int ch;

    panel = activeRight;
    if (panel == 0) { diskId = leftDisk; sel = leftSel; } else { diskId = rightDisk; sel = rightSel; }

    if (panel == 0) { if (leftCount == 0) { return 0; } } else { if (rightCount == 0) { return 0; } }
    if (panel == 0) { if (leftIsDir[sel] == 1) { return 0; } } else { if (rightIsDir[sel] == 1) { return 0; } }

    sync_disk_to_panel(panel);

    i = 0;
    while (i < 12) {
        if (panel == 0) { ch = leftNames[sel * 12 + i]; } else { ch = rightNames[sel * 12 + i]; }
        cmdArgs[i] = ch;
        i = i + 1;
    }
    poke(CMD_ARGS_LEN, 12);

    d_set_name_char(diskId, 0, 69);    // E
    d_set_name_char(diskId, 1, 68);    // D
    d_set_name_char(diskId, 2, 73);    // I
    d_set_name_char(diskId, 3, 84);    // T
    d_set_name_char(diskId, 4, 46);    // .
    d_set_name_char(diskId, 5, 82);    // R
    d_set_name_char(diskId, 6, 85);    // U
    d_set_name_char(diskId, 7, 78);    // N
    d_set_name_char(diskId, 8, 0);
    d_set_name_char(diskId, 9, 0);
    d_set_name_char(diskId, 10, 0);
    d_set_name_char(diskId, 11, 0);

    poke(EXEC_CHILD_DISK, diskId);
    exec_child();

    clear_screen();
    render_left();
    render_right();
    render_status();

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

    if (sel == 0) {
        if (depth > 0) { go_up_dir(); return 0; }   // выбран ".." - подняться, а не CHDIR
    }

    if (isDir == 0) {
        if (is_run_file(activeRight, sel) == 1) { run_program(); }
        return 0;
    }
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

int do_move() {
    // F6 - перенос: тот же байтовый цикл копирования, что do_copy()
    // выше (те же ограничения v1 - папки не переносим, "сам в себя" не
    // переносим - для переноса это даже важнее: без этой защиты чтение
    // и DELETE ЕЩЁ НЕ ДОЧИТАННОГО файла его бы испортили), но после
    // успешного копирования ИСТОЧНИК удаляется (DELETE=9, тот же приём,
    // что perform_delete()), и обновляются ОБЕ панели - файл пропал из
    // одной, появился в другой (do_copy() обновляет только приёмник).
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
    if (isDir == 1) { return 0; }   // папки не переносим в v1 (".." тоже isDir==1 - защищена тем же guard'ом)

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

    // Копия готова - теперь удалить источник. ВАЖНО: если srcDisk и
    // dstDisk - один и тот же физический диск (перенос между двумя
    // папками ОДНОГО диска), currentDir на нём сейчас стоит в папке
    // ПРИЁМНИКА (его туда поставил sync_disk_to_panel(dstPanel) перед
    // OPEN_WRITE) - без повторной синхронизации на srcPanel DELETE
    // удалил бы файл не там (в папке назначения, а не источника).
    sync_disk_to_panel(srcPanel);
    i = 0;
    while (i < 12) {
        if (activeRight == 0) { ch = leftNames[sel * 12 + i]; } else { ch = rightNames[sel * 12 + i]; }
        d_set_name_char(srcDisk, i, ch);
        i = i + 1;
    }
    d_cmd(srcDisk, 9);   // DELETE

    populate_left();
    render_left();
    populate_right();
    render_right();

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
    confirmPending = 0;
    inputPending = 0;

    populate_left();
    populate_right();

    render_left();
    render_right();
    render_status();

    running = 1;
    while (running == 1) {
        key = peek(KEY_DATA);

        if (confirmPending == 1) {
            // Диалог подтверждения удаления (F8) - все обычные клавиши
            // игнорируются, пока не придёт один из этих четырёх кодов.
            if (key == 89)  { confirmPending = 0; perform_delete(); }   // Y
            if (key == 121) { confirmPending = 0; perform_delete(); }   // y
            if (key == 13)  { confirmPending = 0; perform_delete(); }   // Enter
            if (key == 78)  { confirmPending = 0; redraw_panels(); }    // N
            if (key == 110) { confirmPending = 0; redraw_panels(); }    // n
            if (key == 27)  { confirmPending = 0; redraw_panels(); }    // Esc
        } else {
            if (inputPending == 1) {
                // Диалог ввода имени новой папки (F7) - обычные клавиши
                // тоже игнорируются; печатаемые символы (кроме '/' -
                // зарезервирован под маркер папки в списках, см.
                // populate_left/right) копятся в mkdirName.
                if (key == 13) {
                    if (mkdirLen > 0) {
                        inputPending = 0;
                        if (inputMode == 0) { perform_mkdir(); } else { perform_rename(); }
                    }
                }   // Enter
                if (key == 27) { inputPending = 0; redraw_panels(); }                          // Esc
                if (key == 8) {
                    if (mkdirLen > 0) { mkdirLen = mkdirLen - 1; mkdirName[mkdirLen] = 0; draw_mkdir_box(); }
                }   // Backspace
                if (key >= 32) {
                    if (key <= 126) {
                        if (key != 47) {
                            if (mkdirLen < 12) {
                                mkdirName[mkdirLen] = key;
                                mkdirLen = mkdirLen + 1;
                                draw_mkdir_box();
                            }
                        }
                    }
                }
            } else {
                if (key == 17) { running = 0; }   // Ctrl+Q

                if (key == 9) { switch_panel(); }   // Tab

                if (key == KEY_UP)   { move_up(); }
                if (key == KEY_DOWN) { move_down(); }

                if (key == 13) { enter_dir(); }     // Enter
                if (key == 8)  { go_up_dir(); }     // Backspace

                if (key == FKEY_F2) { request_rename(); }   // F2
                if (key == FKEY_F3) { view_selected_file(); }   // F3
                if (key == FKEY_F4) { edit_selected_file(); }   // F4
                if (key == FKEY_F5) { do_copy(); }   // F5
                if (key == FKEY_F6) { do_move(); }   // F6
                if (key == FKEY_F7) { request_mkdir(); }   // F7
                if (key == FKEY_F8) { request_delete(); }   // F8
                if (key == FKEY_F10) { build_selected_file(); }   // F10

                if (key == ALT_F1) { select_disk_left(); }
                if (key == ALT_F2) { select_disk_right(); }
            }
        }

        wait_ms(80);
    }

    clear_screen();

    return 0;
}
