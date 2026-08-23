// EDIT.MC - полноэкранный текстовый редактор на мини-C (см.
// ASSEMBLY.md, "Мини-C"). Имя файла приходит ПЕРВЫМ аргументом
// (CMD_ARGS_LEN/cmdArgs), обычно запускается из C/TOOLS/FM.MC по F4
// (см. edit_selected_file() в FM.MC), но точно так же работает при
// ручном запуске из шелла: "exec edit.mc ИМЯ.ТХТ" или (после
// "build edit.mc") "edit ИМЯ.ТХТ". Если файла с таким именем нет -
// открывается новый пустой файл (в отличие от VIEW.MC, который в этом
// случае отказывается).
//
// В ПАМЯТИ хранится ВЕСЬ файл целиком (в отличие от VIEW.MC,
// который читает файл заново при каждой странице) - у Мини-C нет
// массивов массивов, а один массив ограничен ~255 элементами
// (8-битный индекс), поэтому каждая строка буфера - ОТДЕЛЬНЫЙ
// именованный массив (line0[80]..line47[80]), а весь доступ к
// содержимому идёт ТОЛЬКО через get_char(row,col)/set_char(row,col,v)
// - это единственное место, где нужен каскад "if (row==N)" по всем 48
// строкам; все остальные функции (вставка/удаление/разбиение/слияние
// строк, загрузка, сохранение, рендер) написаны через get_char/
// set_char и lineLen[]/lineCount, каскад больше нигде не всплывает.
// MAX_LINES=48/MAX_COLS=80 - компромисс по объёму кода (2 экрана
// прокрутки), не жёсткий технический потолок - расширяется без
// переделки алгоритмов, только больше однообразных строк.
//
// Файл длиннее MAX_LINES строк или со строкой длиннее MAX_COLS
// символов открывается УСЕЧЁННЫМ (fileTruncated=1, видно в статус-баре
// как "TRUNCATED") - не тихая потеря данных. Сохранение усечённого
// буфера ("^S") требует отдельного подтверждения Y/N, т.к. НАВСЕГДА
// теряет отброшенный хвост исходного файла.
//
// Управление: стрелки - перемещение курсора, Enter - разбить строку,
// Backspace/Delete - удалить символ (на границе строки - слить с
// соседней), Home/End - начало/конец строки, PgUp/PgDn - на экран
// вверх/вниз, Ctrl+S - сохранить, Esc - выход (если есть несохранённые
// правки - модалка Y/N/Esc: Y - сохранить и выйти, N - выйти без
// сохранения, Esc - отмена, остаться в редакторе).
//
// ВНИМАНИЕ: Left/Right/Home/End/PgUp/PgDn/Delete (75/77/71/79/73/81/83)
// и Ctrl+S (19) - коды, ожидаемые по стандартной MS-DOS/conio таблице
// расширенных клавиш (Keyboard.cpp пропускает _getch() без фильтрации,
// та же схема, что уже подтверждённые Up=72/Down=80), но НИ РАЗУ не
// проверялись в этом проекте эмпирически - требуют проверки в живой
// VM. Если код неверен - правится только таблица клавиш ниже, логика
// редактирования не затронута.
//
// Собирается командой "build edit.mc", запускается как "edit ИМЯ".

#include "DISKIO.MC"
#include "STRLIB.MC"

const MAX_LINES = 48;     // ~2 экрана прокрутки - см. комментарий выше
const MAX_COLS  = 80;     // ширина VRAM

const KEY_ESC = 27;
const KEY_ENTER = 13;
const KEY_BACKSPACE = 8;
const KEY_UP = 72;
const KEY_DOWN = 80;
const KEY_LEFT = 75;      // не подтверждено эмпирически, см. шапку файла
const KEY_RIGHT = 77;     // не подтверждено эмпирически
const KEY_HOME = 71;      // не подтверждено эмпирически
const KEY_END = 79;       // не подтверждено эмпирически
const KEY_PGUP = 73;      // не подтверждено эмпирически
const KEY_PGDN = 81;      // не подтверждено эмпирически
const KEY_DELETE = 83;    // не подтверждено эмпирически
const KEY_CTRL_S = 19;    // выведено по формуле "буква-64", не подтверждено эмпирически

// ---- буфер (48 отдельных массивов - см. шапку файла) ----
int line0[MAX_COLS]; int line1[MAX_COLS]; int line2[MAX_COLS]; int line3[MAX_COLS];
int line4[MAX_COLS]; int line5[MAX_COLS]; int line6[MAX_COLS]; int line7[MAX_COLS];
int line8[MAX_COLS]; int line9[MAX_COLS]; int line10[MAX_COLS]; int line11[MAX_COLS];
int line12[MAX_COLS]; int line13[MAX_COLS]; int line14[MAX_COLS]; int line15[MAX_COLS];
int line16[MAX_COLS]; int line17[MAX_COLS]; int line18[MAX_COLS]; int line19[MAX_COLS];
int line20[MAX_COLS]; int line21[MAX_COLS]; int line22[MAX_COLS]; int line23[MAX_COLS];
int line24[MAX_COLS]; int line25[MAX_COLS]; int line26[MAX_COLS]; int line27[MAX_COLS];
int line28[MAX_COLS]; int line29[MAX_COLS]; int line30[MAX_COLS]; int line31[MAX_COLS];
int line32[MAX_COLS]; int line33[MAX_COLS]; int line34[MAX_COLS]; int line35[MAX_COLS];
int line36[MAX_COLS]; int line37[MAX_COLS]; int line38[MAX_COLS]; int line39[MAX_COLS];
int line40[MAX_COLS]; int line41[MAX_COLS]; int line42[MAX_COLS]; int line43[MAX_COLS];
int line44[MAX_COLS]; int line45[MAX_COLS]; int line46[MAX_COLS]; int line47[MAX_COLS];

int lineLen[MAX_LINES];   // фактическая длина каждой строки
int lineCount;            // сколько строк реально используется

int cursorRow;
int cursorCol;
int scrollTop;             // вертикальная прокрутка (первая видимая строка буфера)

int dirty;                 // 1 = есть несохранённые правки
int fileTruncated;         // 1 = часть файла не влезла при загрузке
int endsWithNewline;       // 1 = исходный файл кончался '\n' (для точного сохранения)
int usesCRLF;              // 1 = исходный файл использовал "\r\n" (Windows) - см. load_file()

int exitConfirmPending;    // Esc при dirty==1 -> Y/N/Esc модалка
int saveWarnPending;       // Ctrl+S при fileTruncated==1 -> предупреждение

int running;

// F-клавиши/стрелки/Home/End/PgUp/PgDn/Delete приходят ДВУМЯ байтами
// подряд - сначала 0, потом сам код (см. шапку файла и FM.MC) - код
// KEY_UP=72 и т.п. ЧИСЛЕННО СОВПАДАЕТ с обычными печатными символами
// ('H'=72, 'P'=80, 'K'=75, 'M'=77) - без этого флага второй байт
// расширенной последовательности одновременно двигал бы курсор И
// вставлял букву в текст. pendingExtended=1 - предыдущий непустой байт
// был 0 (начало расширенной последовательности) - следующий непустой
// байт трактуем ТОЛЬКО как код клавиши, не как печатный символ.
int pendingExtended;

// ---- диалоговые окна (локальная адаптация FM.MC::draw_confirm_box(),
// свои константы - EDIT.MC не разделяет память с FM.MC) ----
const DLG_X = 20;
const DLG_Y = 9;
const DLG_W = 40;
const DLG_H = 5;

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

// ---- get_char/set_char - ЕДИНСТВЕННОЕ место с 48-веточным
// диспетчером (см. шапку файла) ----

int get_char(int row, int col) {
    if (row == 0) { return line0[col]; }
    if (row == 1) { return line1[col]; }
    if (row == 2) { return line2[col]; }
    if (row == 3) { return line3[col]; }
    if (row == 4) { return line4[col]; }
    if (row == 5) { return line5[col]; }
    if (row == 6) { return line6[col]; }
    if (row == 7) { return line7[col]; }
    if (row == 8) { return line8[col]; }
    if (row == 9) { return line9[col]; }
    if (row == 10) { return line10[col]; }
    if (row == 11) { return line11[col]; }
    if (row == 12) { return line12[col]; }
    if (row == 13) { return line13[col]; }
    if (row == 14) { return line14[col]; }
    if (row == 15) { return line15[col]; }
    if (row == 16) { return line16[col]; }
    if (row == 17) { return line17[col]; }
    if (row == 18) { return line18[col]; }
    if (row == 19) { return line19[col]; }
    if (row == 20) { return line20[col]; }
    if (row == 21) { return line21[col]; }
    if (row == 22) { return line22[col]; }
    if (row == 23) { return line23[col]; }
    if (row == 24) { return line24[col]; }
    if (row == 25) { return line25[col]; }
    if (row == 26) { return line26[col]; }
    if (row == 27) { return line27[col]; }
    if (row == 28) { return line28[col]; }
    if (row == 29) { return line29[col]; }
    if (row == 30) { return line30[col]; }
    if (row == 31) { return line31[col]; }
    if (row == 32) { return line32[col]; }
    if (row == 33) { return line33[col]; }
    if (row == 34) { return line34[col]; }
    if (row == 35) { return line35[col]; }
    if (row == 36) { return line36[col]; }
    if (row == 37) { return line37[col]; }
    if (row == 38) { return line38[col]; }
    if (row == 39) { return line39[col]; }
    if (row == 40) { return line40[col]; }
    if (row == 41) { return line41[col]; }
    if (row == 42) { return line42[col]; }
    if (row == 43) { return line43[col]; }
    if (row == 44) { return line44[col]; }
    if (row == 45) { return line45[col]; }
    if (row == 46) { return line46[col]; }
    if (row == 47) { return line47[col]; }
    return 0;
}

int set_char(int row, int col, int value) {
    if (row == 0) { line0[col] = value; return 0; }
    if (row == 1) { line1[col] = value; return 0; }
    if (row == 2) { line2[col] = value; return 0; }
    if (row == 3) { line3[col] = value; return 0; }
    if (row == 4) { line4[col] = value; return 0; }
    if (row == 5) { line5[col] = value; return 0; }
    if (row == 6) { line6[col] = value; return 0; }
    if (row == 7) { line7[col] = value; return 0; }
    if (row == 8) { line8[col] = value; return 0; }
    if (row == 9) { line9[col] = value; return 0; }
    if (row == 10) { line10[col] = value; return 0; }
    if (row == 11) { line11[col] = value; return 0; }
    if (row == 12) { line12[col] = value; return 0; }
    if (row == 13) { line13[col] = value; return 0; }
    if (row == 14) { line14[col] = value; return 0; }
    if (row == 15) { line15[col] = value; return 0; }
    if (row == 16) { line16[col] = value; return 0; }
    if (row == 17) { line17[col] = value; return 0; }
    if (row == 18) { line18[col] = value; return 0; }
    if (row == 19) { line19[col] = value; return 0; }
    if (row == 20) { line20[col] = value; return 0; }
    if (row == 21) { line21[col] = value; return 0; }
    if (row == 22) { line22[col] = value; return 0; }
    if (row == 23) { line23[col] = value; return 0; }
    if (row == 24) { line24[col] = value; return 0; }
    if (row == 25) { line25[col] = value; return 0; }
    if (row == 26) { line26[col] = value; return 0; }
    if (row == 27) { line27[col] = value; return 0; }
    if (row == 28) { line28[col] = value; return 0; }
    if (row == 29) { line29[col] = value; return 0; }
    if (row == 30) { line30[col] = value; return 0; }
    if (row == 31) { line31[col] = value; return 0; }
    if (row == 32) { line32[col] = value; return 0; }
    if (row == 33) { line33[col] = value; return 0; }
    if (row == 34) { line34[col] = value; return 0; }
    if (row == 35) { line35[col] = value; return 0; }
    if (row == 36) { line36[col] = value; return 0; }
    if (row == 37) { line37[col] = value; return 0; }
    if (row == 38) { line38[col] = value; return 0; }
    if (row == 39) { line39[col] = value; return 0; }
    if (row == 40) { line40[col] = value; return 0; }
    if (row == 41) { line41[col] = value; return 0; }
    if (row == 42) { line42[col] = value; return 0; }
    if (row == 43) { line43[col] = value; return 0; }
    if (row == 44) { line44[col] = value; return 0; }
    if (row == 45) { line45[col] = value; return 0; }
    if (row == 46) { line46[col] = value; return 0; }
    if (row == 47) { line47[col] = value; return 0; }
    return 0;
}

// ---- операции над строками (только через get_char/set_char) ----

int copy_line(int src, int dst) {
    int i;
    int len;
    len = lineLen[src];
    i = 0;
    while (i < len) { set_char(dst, i, get_char(src, i)); i = i + 1; }
    lineLen[dst] = len;
    return 0;
}

// освобождает строку insertAt, сдвигая insertAt..lineCount-1 вниз на
// одну - вызывающий код ДОЛЖЕН проверить lineCount < MAX_LINES ДО
// вызова
int shift_lines_down(int insertAt) {
    int r;
    r = lineCount;
    while (r > insertAt) { copy_line(r - 1, r); r = r - 1; }
    return 0;
}

// убирает строку fromRow, сдвигая fromRow+1..lineCount-1 вверх на одну
// (lineCount - ещё СТАРОЕ значение на момент вызова, вызывающий код
// уменьшает его после)
int shift_lines_up(int fromRow) {
    int r;
    r = fromRow;
    while (r < lineCount - 1) { copy_line(r + 1, r); r = r + 1; }
    return 0;
}

// ---- загрузка ----

int load_file(int diskId) {
    int ch;
    int col;
    int done;
    int pendingCR;
    int handled;

    diskio_cmd(diskId, DISKIO_OPEN_READ);
    if (diskio_status(diskId) == 2) {
        // файла нет - трактуем как НОВЫЙ пустой файл
        lineCount = 1;
        lineLen[0] = 0;
        endsWithNewline = 1;
        fileTruncated = 0;
        usesCRLF = 0;
        return 0;
    }

    lineCount = 0;
    col = 0;
    fileTruncated = 0;
    endsWithNewline = 1;
    usesCRLF = 0;
    pendingCR = 0;
    done = 0;

    // '\r' (13) сам по себе НЕ считается разделителем строк и никогда
    // не попадает в буфер напрямую - если хранить его как обычный
    // символ (файл с Windows-переводом строк "\r\n"), при выводе на
    // реальный терминал (TextVRAM::render() -> writeUtf8()) он
    // печатается КАК НАСТОЯЩИЙ возврат каретки - терминал перематывает
    // курсор в начало ТЕКУЩЕЙ строки, и всё, что рисуется после,
    // накладывается на уже напечатанное - экран выглядит как "мусор,
    // текста не видно" (реальный баг, найден на game1.txt). "\r\n"
    // трактуется как один перевод строки (usesCRLF=1 - для точного
    // сохранения в том же формате), одиночный "\r" (не перед '\n') -
    // редкий случай, сохраняется как обычный символ.
    while (done == 0) {
        diskio_cmd(diskId, DISKIO_READ_BYTE);
        if (diskio_status(diskId) == 1) {
            // EOF
            if (pendingCR == 1) {
                if (lineCount < MAX_LINES) {
                    if (col < MAX_COLS) { set_char(lineCount, col, 13); col = col + 1; }
                    else { fileTruncated = 1; }
                }
                pendingCR = 0;
            }
            if (col > 0) {
                if (lineCount < MAX_LINES) {
                    lineLen[lineCount] = col;
                    lineCount = lineCount + 1;
                } else {
                    fileTruncated = 1;
                }
                endsWithNewline = 0;   // последняя строка без '\n' в конце
            }
            done = 1;
        } else {
            ch = diskio_data(diskId);
            handled = 0;

            if (pendingCR == 1) {
                pendingCR = 0;
                if (ch == 10) {
                    usesCRLF = 1;
                    if (lineCount < MAX_LINES) {
                        lineLen[lineCount] = col;
                        lineCount = lineCount + 1;
                    } else {
                        fileTruncated = 1;
                    }
                    col = 0;
                    handled = 1;
                } else {
                    // одиночный '\r' (не перед '\n') - сохраняем как обычный символ
                    if (lineCount < MAX_LINES) {
                        if (col < MAX_COLS) { set_char(lineCount, col, 13); col = col + 1; }
                        else { fileTruncated = 1; }
                    }
                }
            }

            if (handled == 0) {
                if (ch == 13) {
                    pendingCR = 1;
                } else {
                    if (ch == 10) {
                        if (lineCount < MAX_LINES) {
                            lineLen[lineCount] = col;
                            lineCount = lineCount + 1;
                        } else {
                            fileTruncated = 1;   // нет места для новой строки
                        }
                        col = 0;
                    } else {
                        if (lineCount < MAX_LINES) {
                            if (col < MAX_COLS) {
                                set_char(lineCount, col, ch);
                                col = col + 1;
                            } else {
                                fileTruncated = 1;   // строка длиннее MAX_COLS - хвост отброшен
                            }
                        }
                        // если lineCount >= MAX_LINES - байт молча пропускается,
                        // fileTruncated уже выставлен веткой '\n' выше
                    }
                }
            }
        }
    }

    diskio_cmd(diskId, DISKIO_CLOSE);

    if (lineCount == 0) { lineCount = 1; lineLen[0] = 0; }   // пустой файл - одна пустая строка
    return 0;
}

// ---- сохранение ----

int save_file(int diskId) {
    int r;
    int c;
    int len;

    diskio_cmd(diskId, DISKIO_OPEN_WRITE);   // усекает файл и открывает на запись

    r = 0;
    while (r < lineCount) {
        len = lineLen[r];
        c = 0;
        while (c < len) {
            diskio_set_data(diskId, get_char(r, c));
            diskio_cmd(diskId, DISKIO_WRITE_BYTE);
            c = c + 1;
        }
        if (r < lineCount - 1) {
            if (usesCRLF == 1) { diskio_set_data(diskId, 13); diskio_cmd(diskId, DISKIO_WRITE_BYTE); }
            diskio_set_data(diskId, 10);
            diskio_cmd(diskId, DISKIO_WRITE_BYTE);
        } else {
            if (endsWithNewline == 1) {
                if (usesCRLF == 1) { diskio_set_data(diskId, 13); diskio_cmd(diskId, DISKIO_WRITE_BYTE); }
                diskio_set_data(diskId, 10);
                diskio_cmd(diskId, DISKIO_WRITE_BYTE);
            }
        }
        r = r + 1;
    }

    diskio_cmd(diskId, DISKIO_CLOSE);
    dirty = 0;
    return 0;
}

// ---- рендер ----

int redraw_line(int bufRow) {
    int sy;
    int x;
    int ch;
    int len;

    sy = bufRow - scrollTop;
    if (sy < 0) { return 0; }
    if (sy > 23) { return 0; }

    len = 0;
    if (bufRow < lineCount) { len = lineLen[bufRow]; }

    x = 0;
    while (x < 80) {
        if (bufRow < lineCount) { if (x < len) { ch = get_char(bufRow, x); } else { ch = 32; } }
        else { ch = 32; }
        print_char(x, sy, ch);
        set_color(x, sy, 7, 0);
        x = x + 1;
    }

    if (bufRow == cursorRow) { set_color(cursorCol, sy, 0, 7); }
    return 0;
}

int draw_status() {
    int i;
    int ch;

    i = 0;
    while (i < 80) { set_color(i, 24, 0, 7); i = i + 1; }

    i = 0;
    while (i < 12) {
        ch = cmdArgs[i];
        if (ch == 0) { ch = 32; }
        print_char(i, 24, ch);
        i = i + 1;
    }
    if (dirty == 1) { print_char(12, 24, 42); }             // '*' - несохранённые правки
    if (fileTruncated == 1) { print_str(14, 24, "TRUNCATED"); }

    print_str(40, 24, "Ln");
    print_number3(43, 24, cursorRow);
    print_str(47, 24, "Col");
    print_number3(51, 24, cursorCol);
    print_str(60, 24, "^S-Save Esc-Exit");

    return 0;
}

int redraw_screen() {
    int y;
    y = 0;
    while (y < 24) { redraw_line(scrollTop + y); y = y + 1; }
    draw_status();
    return 0;
}

int clamp_cursor() {
    if (cursorRow < 0) { cursorRow = 0; }
    if (cursorRow > lineCount - 1) { cursorRow = lineCount - 1; }
    if (cursorCol < 0) { cursorCol = 0; }
    if (cursorCol > lineLen[cursorRow]) { cursorCol = lineLen[cursorRow]; }
    return 0;
}

int move_cursor(int newRow, int newCol) {
    int oldRow;
    int needFull;

    oldRow = cursorRow;
    cursorRow = newRow;
    cursorCol = newCol;
    clamp_cursor();

    needFull = 0;
    if (cursorRow < scrollTop) { scrollTop = cursorRow; needFull = 1; }
    if (cursorRow > scrollTop + 23) { scrollTop = cursorRow - 23; needFull = 1; }

    if (needFull == 1) { redraw_screen(); }
    else { redraw_line(oldRow); redraw_line(cursorRow); draw_status(); }
    return 0;
}

// как move_cursor(), но ВСЕГДА полный редрау экрана - нужно после
// операций, которые сдвигают МНОГО строк разом (разбиение/слияние
// строк - handle_enter()/join_with_next()), где move_cursor()'s
// дешёвая перерисовка только старой+новой строки курсора оставила бы
// все строки НИЖЕ места правки со старым (уже неактуальным)
// содержимым на экране
int move_cursor_full(int newRow, int newCol) {
    cursorRow = newRow;
    cursorCol = newCol;
    clamp_cursor();

    if (cursorRow < scrollTop) { scrollTop = cursorRow; }
    if (cursorRow > scrollTop + 23) { scrollTop = cursorRow - 23; }

    redraw_screen();
    return 0;
}

// ---- редактирование ----

// вставляет ch в row на позицию col, сдвигая хвост строки вправо -
// отказ (без порчи данных), если строка уже MAX_COLS
int insert_char(int row, int col, int ch) {
    int i;
    int len;
    len = lineLen[row];
    if (len >= MAX_COLS) { return 0; }
    i = len;
    while (i > col) { set_char(row, i, get_char(row, i - 1)); i = i - 1; }
    set_char(row, col, ch);
    lineLen[row] = len + 1;
    dirty = 1;
    return 1;
}

// удаляет символ В col, сдвигая хвост строки влево
int delete_char(int row, int col) {
    int i;
    int len;
    len = lineLen[row];
    if (col >= len) { return 0; }
    i = col;
    while (i < len - 1) { set_char(row, i, get_char(row, i + 1)); i = i + 1; }
    lineLen[row] = len - 1;
    dirty = 1;
    return 1;
}

// разбивает текущую строку по курсору - отказ, если буфер уже полон
int handle_enter() {
    int tailLen;
    int i;
    int newRow;

    if (lineCount >= MAX_LINES) { return 0; }

    newRow = cursorRow + 1;
    shift_lines_down(newRow);
    lineCount = lineCount + 1;

    tailLen = lineLen[cursorRow] - cursorCol;
    i = 0;
    while (i < tailLen) { set_char(newRow, i, get_char(cursorRow, cursorCol + i)); i = i + 1; }
    lineLen[newRow] = tailLen;
    lineLen[cursorRow] = cursorCol;

    dirty = 1;
    move_cursor_full(newRow, 0);
    return 1;
}

// сливает row и row+1 в row - отказ, если результат не влезает в MAX_COLS
int join_with_next(int row) {
    int prevLen;
    int curLen;
    int i;

    if (row >= lineCount - 1) { return 0; }
    prevLen = lineLen[row];
    curLen = lineLen[row + 1];
    if (prevLen + curLen > MAX_COLS) { return 0; }

    i = 0;
    while (i < curLen) { set_char(row, prevLen + i, get_char(row + 1, i)); i = i + 1; }
    lineLen[row] = prevLen + curLen;

    shift_lines_up(row + 1);
    lineCount = lineCount - 1;
    dirty = 1;
    return 1;
}

int handle_backspace() {
    int prevLen;

    if (cursorCol > 0) {
        delete_char(cursorRow, cursorCol - 1);
        move_cursor(cursorRow, cursorCol - 1);
        return 0;
    }

    if (cursorRow > 0) {
        prevLen = lineLen[cursorRow - 1];
        if (join_with_next(cursorRow - 1) == 1) {
            move_cursor_full(cursorRow - 1, prevLen);
        }
    }
    return 0;
}

int handle_delete() {
    if (cursorCol < lineLen[cursorRow]) {
        delete_char(cursorRow, cursorCol);
        redraw_line(cursorRow);
        draw_status();
        return 0;
    }

    join_with_next(cursorRow);
    redraw_screen();
    return 0;
}

int handle_printable(int ch) {
    if (insert_char(cursorRow, cursorCol, ch) == 1) {
        move_cursor(cursorRow, cursorCol + 1);
    }
    return 0;
}

// ---- модальные диалоги (Y/N/Esc) ----

int draw_dialog_frame() {
    int x;
    int y;

    print_char(DLG_X, DLG_Y, 201);
    print_char(DLG_X + DLG_W - 1, DLG_Y, 187);
    x = DLG_X + 1;
    while (x < DLG_X + DLG_W - 1) { print_char(x, DLG_Y, 205); x = x + 1; }

    y = DLG_Y + 1;
    while (y < DLG_Y + DLG_H - 1) {
        print_char(DLG_X, y, 186);
        print_char(DLG_X + DLG_W - 1, y, 186);
        x = DLG_X + 1;
        while (x < DLG_X + DLG_W - 1) { print_char(x, y, 32); x = x + 1; }
        y = y + 1;
    }

    print_char(DLG_X, DLG_Y + DLG_H - 1, 200);
    print_char(DLG_X + DLG_W - 1, DLG_Y + DLG_H - 1, 188);
    x = DLG_X + 1;
    while (x < DLG_X + DLG_W - 1) { print_char(x, DLG_Y + DLG_H - 1, 205); x = x + 1; }

    y = DLG_Y;
    while (y < DLG_Y + DLG_H) {
        x = DLG_X;
        while (x < DLG_X + DLG_W) { set_color(x, y, 14, 1); x = x + 1; }
        y = y + 1;
    }

    return 0;
}

int draw_exit_confirm_box() {
    draw_dialog_frame();
    print_str(DLG_X + 2, DLG_Y + 1, "Save changes before exit?");
    print_str(DLG_X + 2, DLG_Y + 3, "Y-Save N-Discard Esc-Cancel");
    return 0;
}

int draw_truncate_warn_box() {
    draw_dialog_frame();
    print_str(DLG_X + 2, DLG_Y + 1, "File was truncated on load -");
    print_str(DLG_X + 2, DLG_Y + 2, "saving will lose the rest!");
    print_str(DLG_X + 2, DLG_Y + 3, "Y-Save anyway  N/Esc-Cancel");
    return 0;
}

int main() {
    int diskId;
    int key;
    int haveKey;

    diskId = peek(EXEC_CHILD_DISK);
    build_name_from_args(diskId);

    load_file(diskId);

    cursorRow = 0;
    cursorCol = 0;
    scrollTop = 0;
    dirty = 0;
    exitConfirmPending = 0;
    saveWarnPending = 0;
    pendingExtended = 0;

    clear_screen();
    redraw_screen();

    running = 1;
    while (running == 1) {
        // peek(KEYBOARD_DATA) САМ ПО СЕБЕ не отличает "очередь пуста"
        // от "реально нажатой клавиши со значением 0" - оба случая
        // отдают 0 (см. Keyboard::read()). Раз стрелки/Home/End и т.п.
        // ПРИХОДЯТ как раз с ведущим нулём (первый байт расширенной
        // последовательности), naive-проверка "key==0" ложно
        // срабатывала на КАЖДЫЙ холостой опрос простоя - pendingExtended
        // почти всегда оставался 1, и обычные однобайтовые клавиши
        // (Esc/Enter/Backspace/буквы) переставали работать вовсе.
        // KEYBOARD_CONTROL, бит HAS_DATA (2) - показывает, была ли в
        // очереди РЕАЛЬНАЯ запись ДО этого чтения - только тогда есть
        // смысл вообще разбирать key.
        // int в Мини-C - 8-бит (0-255) - "key = 256;" в качестве
        // маркера "клавиш не было" МОЛЧА заворачивается в 0 (256 mod
        // 256), снова неотличимо от настоящего ведущего нуля - нужен
        // ОТДЕЛЬНЫЙ флаг haveKey, а не значение вне диапазона key.
        haveKey = 0;
        if ((peek(KEYBOARD_CONTROL) & 2) != 0) {
            key = peek(KEYBOARD_DATA);
            haveKey = 1;
        }

        // haveKey==0 - ничего не нажато сейчас - pendingExtended (если
        // уже был выставлен настоящим ведущим нулём) остаётся ждать
        // свой код клавиши на будущих итерациях, не сбрасываем - весь
        // разбор ниже просто пропускается.
        if (haveKey == 1) {
            if (key == 0) {
                // настоящий ведущий байт расширенной последовательности
                // (в очереди ДЕЙСТВИТЕЛЬНО что-то было, HAS_DATA это
                // подтвердил) - код клавиши придёт следующим чтением.
                // 0 - префикс Windows _getch() для Ф-клавиш (F1-F10).
                pendingExtended = 1;
            } else {
            if (key == 224) {
                // 0xE0 (224) - ДРУГОЙ префикс _getch(), для стрелок/
                // Home/End/PgUp/PgDn/Delete/Insert/F11/F12 - без этой
                // ветки их настоящий код (72/80/75/77 и т.п. -
                // ЧИСЛЕННО совпадает с буквами 'H'/'P'/'K'/'M') летел
                // мимо pendingExtended прямо в handle_printable()
                // ("стрелки печатают буквы вместо движения курсора").
                pendingExtended = 1;
            } else {
            if (exitConfirmPending == 1) {
                pendingExtended = 0;   // диалогам стрелки/спецклавиши не нужны
                if (key == 89)  { exitConfirmPending = 0; save_file(diskId); running = 0; }   // Y
                if (key == 121) { exitConfirmPending = 0; save_file(diskId); running = 0; }   // y
                if (key == 78)  { exitConfirmPending = 0; running = 0; }                      // N
                if (key == 110) { exitConfirmPending = 0; running = 0; }                      // n
                if (key == KEY_ESC) { exitConfirmPending = 0; redraw_screen(); }
            } else {
                if (saveWarnPending == 1) {
                    pendingExtended = 0;
                    if (key == 89)  { saveWarnPending = 0; save_file(diskId); redraw_screen(); }
                    if (key == 121) { saveWarnPending = 0; save_file(diskId); redraw_screen(); }
                    if (key == 78)  { saveWarnPending = 0; redraw_screen(); }
                    if (key == 110) { saveWarnPending = 0; redraw_screen(); }
                    if (key == KEY_ESC) { saveWarnPending = 0; redraw_screen(); }
                } else {
                    if (pendingExtended == 1) {
                        // второй байт расширенной последовательности -
                        // ТОЛЬКО код клавиши, ни в коем случае не текст
                        // (иначе 'H'/'P'/'K'/'M' от KEY_UP/DOWN/LEFT/
                        // RIGHT долетали бы до handle_printable())
                        pendingExtended = 0;

                        if (key == KEY_UP)    { move_cursor(cursorRow - 1, cursorCol); }
                        if (key == KEY_DOWN)  { move_cursor(cursorRow + 1, cursorCol); }
                        if (key == KEY_LEFT) {
                            if (cursorCol > 0) { move_cursor(cursorRow, cursorCol - 1); }
                            else { if (cursorRow > 0) { move_cursor(cursorRow - 1, lineLen[cursorRow - 1]); } }
                        }
                        if (key == KEY_RIGHT) {
                            if (cursorCol < lineLen[cursorRow]) { move_cursor(cursorRow, cursorCol + 1); }
                            else { if (cursorRow < lineCount - 1) { move_cursor(cursorRow + 1, 0); } }
                        }
                        if (key == KEY_HOME)  { move_cursor(cursorRow, 0); }
                        if (key == KEY_END)   { move_cursor(cursorRow, lineLen[cursorRow]); }
                        if (key == KEY_PGUP)  { move_cursor(cursorRow - 24, cursorCol); }
                        if (key == KEY_PGDN)  { move_cursor(cursorRow + 24, cursorCol); }
                        if (key == KEY_DELETE) { handle_delete(); }
                    } else {
                        // обычная однобайтовая клавиша - Esc/Enter/
                        // Backspace/Ctrl+S/печатный символ
                        if (key == KEY_ESC) {
                            if (dirty == 0) { running = 0; }
                            else { exitConfirmPending = 1; draw_exit_confirm_box(); }
                        }
                        if (key == KEY_CTRL_S) {
                            if (dirty == 1) {
                                if (fileTruncated == 1) { saveWarnPending = 1; draw_truncate_warn_box(); }
                                else { save_file(diskId); draw_status(); }
                            }
                        }

                        if (key == KEY_ENTER) { handle_enter(); }
                        if (key == KEY_BACKSPACE) { handle_backspace(); }

                        if (key >= 32) {
                            if (key <= 126) { handle_printable(key); }
                        }
                    }
                }
            }
            }
            }
        }

        wait_ms(20);
    }

    return 0;
}
