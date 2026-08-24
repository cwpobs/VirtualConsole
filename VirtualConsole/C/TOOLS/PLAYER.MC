// PLAYER.MC - проигрыватель трекерной музыки (.mod) с живым
// визуализатором в текстовом псевдографическом режиме, "в духе"
// Impulse Tracker: рамка, статус/Order/Row и четыре горизонтальных
// VU-метра, по одному на канал ProTracker (данные - из read-only
// регистров визуализации SoundCard: CHANNEL0-3_VOLUME/ROW/ORDER_POS,
// см. ASSEMBLY.md, "SoundCard").
//
// Два режима запуска:
//
//   player SPACE_~1.MOD          - один трек, имя параметром (как раньше)
//   player                       - плейлист: читает PLAY.LST рядом с
//                                   собой, показывает список (стрелки +
//                                   Enter, подсказки внизу, как в FM.MC)
//
// Имя .mod для режима "один трек" передаётся параметром командной строки
// (см. ASSEMBLY.md, "Аргументы командной строки"):
//
//     player SPACE_~1.MOD
//     exec player.mc SPACE_~1.MOD
//
// ВАЖНО: аргумент командной строки идёт через cmdArgs[16]/CMD_ARGS_LEN
// - буфер шириной РОВНО 16 байт (см. ASSEMBLY.md) - имена .mod-файлов
// длиннее 16 байт не поместятся целиком и будут молча обрезаны. Имена
// диска и так ограничены 8.3 (см. "Disk"/"ModLoader" в ASSEMBLY.md) -
// длинное имя вроде "space_debris.mod" в самой файловой системе VM
// невозможно, для него используется DOS-стиль "SPACE_~1.MOD" (~1, как
// в настоящем DOS при обрезании длинных имён).
//
// PLAY.LST (режим "плейлист") - текстовый файл рядом с PLAYER.RUN
// (C/TOOLS/PLAY.LST), одна строка на трек: "<ДИСК>/<путь от корня
// диска>", например "C/DEMOS/SPACE_~1.MOD" или "D/GAMES/SONG.MOD" -
// см. load_playlist()/load_mod_from_playlist() ниже и ASSEMBLY.md,
// раздел "Плейлист (PLAY.LST)". До 16 строк, без прокрутки; лишние
// строки молча игнорируются.
//
// mod_load() из Мини-C принимает только строковый ЛИТЕРАЛ, известный на
// этапе компиляции (см. ASSEMBLY.md, "Звук и музыка: mod_load()/
// sound_*()") - для рантайм-имени (наш случай, имя приходит параметром
// или строкой плейлиста) программа сама копирует байты в NAME-буфер
// ModLoader (0xF0001020-0xF000103F, маппированный массив modName[32]) и
// вручную триггерит COMMAND=LOAD - тот же приём, что MUSIC.ASM когда-то
// делал руками на голом ассемблере, но для одного зашитого имени.
// Проверено: байт в байт тот же код, что генерирует mod_load() на этапе
// компиляции (см. Compiler.cpp::genModLoad) - разницы в РЕЗУЛЬТАТЕ нет.
//
// Управление во время проигрывания: Ctrl+Q - остановить и выйти из
// плеера целиком (из ЛЮБОГО режима запуска), P - пауза/продолжить. В
// режиме плейлиста дополнительно: Esc - остановить и вернуться к
// списку, стрелки влево/вправо - предыдущий/следующий трек БЕЗ
// зацикливания (на первом треке влево и на последнем вправо - молча
// ничего не делают, трек не прерывается). Текущее время трека (мм:сс с
// начала, не общая длительность - MOD-файлы её не хранят, а честно
// посчитать нельзя без учёта Fxx-эффектов смены темпа внутри песни, см.
// ASSEMBLY.md/SoundCard) - в углу экрана, рядом с Order/Row.
//
// Управление в списке плейлиста: стрелки вверх/вниз - выбор, Enter -
// играть, Ctrl+Q - выход из плеера.
//
// Собирается командой "build player.mc", запускается как "player" или
// "player ИМЯ.MOD".

#include "STRLIB.MC"
#include "DISKIO.MC"

const MODLOADER_COMMAND     = 0xF0001040;
const MODLOADER_STATUS      = 0xF0001041;
const MODLOADER_DISK_SELECT = 0xF0001043;   // 0=как раньше (lastExecDisk), 1=диск C, 2=диск D - см. ModLoaderDiskSelect.h

const SOUNDCARD_COMMAND    = 0xF0001066;
const SOUNDCARD_STATUS     = 0xF0001067;
const SOUNDCARD_ROW        = 0xF000106D;
const SOUNDCARD_ORDER_POS  = 0xF000106E;

// "Едущие блоки" - живой просмотр ноты/сэмпла/эффекта в ТЕКУЩЕМ играющем
// паттерне (см. ASSEMBLY.md, "SoundCard"): пишем PATTERN_ROW_SELECT/
// PATTERN_CHANNEL_SELECT, читаем обратно четыре поля ячейки. Только
// текущий паттерн - строка, уехавшая за его начало/конец (0-63), не
// подтягивает соседний паттерн, а просто рисуется пустой (см.
// draw_pattern_view() ниже).
const SOUNDCARD_PATTERN_ROW_SELECT     = 0xF000106F;
const SOUNDCARD_PATTERN_CHANNEL_SELECT = 0xF0001070;
const SOUNDCARD_PATTERN_NOTE           = 0xF0001071;
const SOUNDCARD_PATTERN_SAMPLE         = 0xF0001072;
const SOUNDCARD_PATTERN_EFFECT         = 0xF0001073;
const SOUNDCARD_PATTERN_PARAM          = 0xF0001074;

const KEY_CTRL_Q  = 17;
const KEY_P_UPPER = 80;
const KEY_P_LOWER = 112;
const KEY_ENTER   = 13;
const KEY_ESC     = 27;
const KEY_UP      = 72;    // стрелка вверх (extended-код _getch(), см. ASSEMBLY.md/Keyboard - как в FM.MC)
const KEY_DOWN    = 80;    // стрелка вниз - совпадает по значению с KEY_P_UPPER, но используется только в меню плейлиста, не в цикле проигрывания, конфликта нет
const KEY_LEFT    = 75;    // стрелка влево (та же extended-таблица - см. TSCROLL.MC/EDIT.MC)
const KEY_RIGHT   = 77;    // стрелка вправо

const BAR_X   = 9;
const BAR_LEN = 58;   // ширина шкалы под громкость канала 0-64

const PLAYLIST_MAX   = 16;   // до 16 треков, без прокрутки (см. заголовок файла)
const PLAYLIST_WIDTH = 36;   // "<ДИСК>/" (2 байта) + до 32 байт (лимит NAME у ModLoader) + запас

// Возвращаемое play_track_loop() ниже - что делать дальше, когда трек
// перестал играть (по любой причине - клавиша или сама завершила бы
// цикл, если бы такое было возможно).
const ACTION_EXIT = 0;   // Ctrl+Q - закрыть плеер целиком
const ACTION_MENU = 1;   // Esc - вернуться к списку плейлиста
const ACTION_NEXT = 2;   // стрелка вправо - следующий трек (без зацикливания)
const ACTION_PREV = 3;   // стрелка влево - предыдущий трек (без зацикливания)

// "Едущие блоки" (см. draw_pattern_view() ниже) - окно из 9 строк вокруг
// текущей (4 до, сама текущая, 4 после), под VU-метрами, в ранее пустых
// строках экрана 13-24 (сам экран 0-24). PATTERN_FIRST_ROW - строка
// экрана для ПЕРВОГО слота окна (слот 4 из 9 - текущая строка паттерна,
// см. main.cpp/SoundCard.h "PATTERN_ROW_SELECT").
const PATTERN_TOP       = 13;   // верхняя рамка
const PATTERN_HEADER    = 14;   // подписи CH1-CH4
const PATTERN_FIRST_ROW = 15;   // первый из 9 слотов окна
const PATTERN_ROWS      = 9;
const PATTERN_BOTTOM    = 24;   // нижняя рамка = PATTERN_FIRST_ROW + PATTERN_ROWS
const PATTERN_CENTER    = 4;    // слот текущей строки (0-8, 4 - середина)

const PATTERN_COL_X0    = 2;    // x первого канала
const PATTERN_COL_WIDTH = 13;   // "C-3 01 A02" (10 символов) + отступ

int modName[32] = 0xF0001020;      // NAME0-31 у ModLoader
int channelVol[4] = 0xF0001069;    // CHANNEL0-3_VOLUME у SoundCard (read-only)

// Имена нот - 3 октавы, тот же порядок, что PERIOD_TABLE в SoundCard.cpp
// (см. ASSEMBLY.md, "SoundCard") - индекс 0-35, заполняется один раз
// init_note_names() (см. main()). Классический трекерный формат "Буква
// диез/дефис октава", например "C-1", "C#1", "D-1"... "B-3".
string noteNames[36][4];

// Плейлист - список путей "<ДИСК>/<путь от корня>" (см. load_playlist()/
// load_mod_from_playlist() ниже). string, а не 16 обычных int-массивов +
// if-каскад (как SNAKE.MC делает для строк экрана) - обычный `int arr[i]`
// упирается в 255 элементов (arr[i] считает офсет через __mc_hladd,
// который жёстко обнуляет старший байт - см. ASSEMBLY.md, "Тип string"),
// а 16*36=576 такому лимиту не подчиняется.
string playlist[PLAYLIST_MAX][PLAYLIST_WIDTH];

// Состояние предыдущего кадра - для delta-перерисовки (см. draw_channel()/
// main() ниже): трогаем экран, только если значение реально изменилось -
// дешевле для CPU-потока и не красит лишний раз то, что и так на месте.
int lastFilled[4];   // длина полоски канала на прошлом кадре, 0-BAR_LEN
int lastVol[4];       // напечатанное число громкости канала на прошлом кадре
int lastStatus;        // STATUS SoundCard на прошлом кадре
int lastOrder;         // ORDER_POS на прошлом кадре
int lastRow;           // ROW на прошлом кадре

// Прошедшее время трека (мм:сс) - см. play_track_loop() ниже. Честной
// длительности MOD-файлы не хранят (движок её не считает, и она всё
// равно "плавает" от Fxx-эффектов смены темпа внутри песни - см.
// ASSEMBLY.md, "SoundCard") - только то, сколько уже играем. Копится
// приблизительно (30 кадров wait_ms(33) ~= 1 секунда, а не настоящие
// показания часов) - для секундомера в углу экрана точность до
// миллисекунды не нужна, а десяток лишних мс на "секунду" не заметны.
int elapsedFrameTick;   // 0-29, кадров с последней целой секунды
int elapsedSec;          // 0-59
int elapsedMin;           // 0-255 (проигрывание длиннее 255 минут не ожидается)

int wait_ms(int ms) {
    poke(CLOCK_LOW, 0);
    while (peek(CLOCK_LOW) < ms) {
    }
    return 0;
}

int wait_key() {
    int haveKey;
    int key;
    haveKey = 0;
    while (haveKey == 0) {
        if ((peek(KEYBOARD_CONTROL) & 2) != 0) {
            key = peek(KEYBOARD_DATA);
            haveKey = 1;
        }
    }
    return 0;
}

// Копирует имя файла из cmdArgs в NAME-буфер ModLoader и триггерит
// LOAD - см. заголовок файла про то, почему это нельзя сделать через
// mod_load(). Возвращает STATUS ModLoader (0=ok,1=не найден,2=плохой
// формат,3=битый - см. ASSEMBLY.md).
int load_mod_from_arg(int argLen) {
    int i;

    i = 0;
    while (i < argLen) {
        modName[i] = cmdArgs[i];
        i = i + 1;
    }
    while (i < 32) {
        modName[i] = 0;
        i = i + 1;
    }

    poke(MODLOADER_COMMAND, 1);   // LOAD
    return peek(MODLOADER_STATUS);
}

int color_text(int x, int y, int len, int fg) {
    int colorTextI;
    colorTextI = 0;
    while (colorTextI < len) {
        set_color(x + colorTextI, y, fg, 0);
        colorTextI = colorTextI + 1;
    }
    return 0;
}

// Сбрасывает состояние delta-перерисовки (см. lastFilled/lastVol/
// lastStatus/lastOrder/lastRow выше) под свежий draw_static() - нужно
// звать перед КАЖДЫМ draw_static(), не только один раз при старте
// программы: теперь draw_static() рисуется заново на каждый новый трек
// (плейлист, Esc/следующий/предыдущий), а не только один раз за запуск.
int reset_delta_state() {
    lastFilled[0] = 0; lastFilled[1] = 0; lastFilled[2] = 0; lastFilled[3] = 0;
    lastVol[0] = 0; lastVol[1] = 0; lastVol[2] = 0; lastVol[3] = 0;
    // int в мини-C - 8 бит (0-255) - сентинелы ниже подобраны заведомо
    // вне реального диапазона каждого регистра (STATUS 0-3, ORDER_POS
    // 0-127, ROW 0-63), но внутри 0-255, чтобы гарантировать первую
    // отрисовку без переполнения литерала.
    lastStatus = 4;
    lastOrder = 255;
    lastRow = 255;
    return 0;
}

int print_number2(int x, int y, int value) {
    int d0;
    int d1;
    d0 = value / 10;
    d1 = value % 10;
    print_char(x, y, d0 + 48);
    print_char(x + 1, y, d1 + 48);
    return 0;
}

// Один hex-символ (0-15 -> '0'-'9'/'A'-'F') и два подряд (0-255 -> два
// символа) - для sample/effect/param в "едущих блоках" (см.
// draw_pattern_view() ниже), тот же формат, что классические трекеры.
int hex_digit(int v) {
    if (v < 10) { return v + 48; }
    return v + 55;   // 10 -> 65 ('A')
}

int print_hex2(int x, int y, int value) {
    print_char(x, y, hex_digit(value / 16));
    print_char(x + 1, y, hex_digit(value % 16));
    return 0;
}

int set_note_name(int idx, int c0, int c1, int c2) {
    noteNames[idx][0] = c0;
    noteNames[idx][1] = c1;
    noteNames[idx][2] = c2;
    noteNames[idx][3] = 0;
    return 0;
}

// Заполняет noteNames[36] - тот же порядок нот, что PERIOD_TABLE в
// SoundCard.cpp (3 октавы: C-1..B-1, C-2..B-2, C-3..B-3). Зовётся один
// раз из main() перед первым использованием. Коды символов: C=67,D=68,
// E=69,F=70,G=71,A=65,B=66, '#'=35, '-'=45, цифры '1'/'2'/'3'=49/50/51.
int init_note_names() {
    set_note_name(0, 67, 45, 49);    // C-1
    set_note_name(1, 67, 35, 49);    // C#1
    set_note_name(2, 68, 45, 49);    // D-1
    set_note_name(3, 68, 35, 49);    // D#1
    set_note_name(4, 69, 45, 49);    // E-1
    set_note_name(5, 70, 45, 49);    // F-1
    set_note_name(6, 70, 35, 49);    // F#1
    set_note_name(7, 71, 45, 49);    // G-1
    set_note_name(8, 71, 35, 49);    // G#1
    set_note_name(9, 65, 45, 49);    // A-1
    set_note_name(10, 65, 35, 49);   // A#1
    set_note_name(11, 66, 45, 49);   // B-1

    set_note_name(12, 67, 45, 50);   // C-2
    set_note_name(13, 67, 35, 50);   // C#2
    set_note_name(14, 68, 45, 50);   // D-2
    set_note_name(15, 68, 35, 50);   // D#2
    set_note_name(16, 69, 45, 50);   // E-2
    set_note_name(17, 70, 45, 50);   // F-2
    set_note_name(18, 70, 35, 50);   // F#2
    set_note_name(19, 71, 45, 50);   // G-2
    set_note_name(20, 71, 35, 50);   // G#2
    set_note_name(21, 65, 45, 50);   // A-2
    set_note_name(22, 65, 35, 50);   // A#2
    set_note_name(23, 66, 45, 50);   // B-2

    set_note_name(24, 67, 45, 51);   // C-3
    set_note_name(25, 67, 35, 51);   // C#3
    set_note_name(26, 68, 45, 51);   // D-3
    set_note_name(27, 68, 35, 51);   // D#3
    set_note_name(28, 69, 45, 51);   // E-3
    set_note_name(29, 70, 45, 51);   // F-3
    set_note_name(30, 70, 35, 51);   // F#3
    set_note_name(31, 71, 45, 51);   // G-3
    set_note_name(32, 71, 35, 51);   // G#3
    set_note_name(33, 65, 45, 51);   // A-3
    set_note_name(34, 65, 35, 51);   // A#3
    set_note_name(35, 66, 45, 51);   // B-3

    return 0;
}

int draw_time() {
    print_number2(56, 2, elapsedMin);
    print_number2(59, 2, elapsedSec);
    return 0;
}

int draw_empty_bar(int row) {
    int x;
    x = 0;
    while (x < BAR_LEN) {
        print_char(BAR_X + x, row, 176);   // ░
        set_color(BAR_X + x, row, 8, 0);
        x = x + 1;
    }
    return 0;
}

// Статическая часть экрана (рамка/подписи) - рисуется один раз, дальше
// каждый кадр обновляются только цифры/метры поверх неё (см. main()).
// playlistMode - какую подсказку внизу показать (см. play_track_loop() -
// Esc/влево/вправо активны только в режиме плейлиста, так что и в
// подсказке им незачем быть, если играем трек, запущенный параметром).
int draw_static(int playlistMode) {
    int x;

    clear_screen();

    print_char(0, 0, 201);   // ╔
    print_char(79, 0, 187);  // ╗
    x = 1;
    while (x < 79) { print_char(x, 0, 205); x = x + 1; }   // ═

    print_char(0, 3, 204);   // ╠
    print_char(79, 3, 185);  // ╣
    x = 1;
    while (x < 79) { print_char(x, 3, 205); x = x + 1; }

    print_char(0, 10, 204);
    print_char(79, 10, 185);
    x = 1;
    while (x < 79) { print_char(x, 10, 205); x = x + 1; }

    print_char(0, 12, 200);  // ╚
    print_char(79, 12, 188); // ╝
    x = 1;
    while (x < 79) { print_char(x, 12, 205); x = x + 1; }

    print_char(0, 1, 186); print_char(79, 1, 186);   // ║
    print_char(0, 2, 186); print_char(79, 2, 186);
    print_char(0, 4, 186); print_char(79, 4, 186);
    print_char(0, 5, 186); print_char(79, 5, 186);
    print_char(0, 6, 186); print_char(79, 6, 186);
    print_char(0, 7, 186); print_char(79, 7, 186);
    print_char(0, 8, 186); print_char(79, 8, 186);
    print_char(0, 9, 186); print_char(79, 9, 186);
    print_char(0, 11, 186); print_char(79, 11, 186);

    // Красим ТОЛЬКО реально нарисованные символы рамки - горизонтальные
    // линии (0/3/10/12) целиком, строки с одними боковыми ║ (1,2,4-9,
    // 11) - только сами эти два столбика, а не всю ширину (пустой
    // интерьер там - обычный пробел, красить его незачем).
    color_text(0, 0, 80, 11);
    set_color(0, 1, 11, 0); set_color(79, 1, 11, 0);
    set_color(0, 2, 11, 0); set_color(79, 2, 11, 0);
    color_text(0, 3, 80, 11);
    set_color(0, 4, 11, 0); set_color(79, 4, 11, 0);
    set_color(0, 5, 11, 0); set_color(79, 5, 11, 0);
    set_color(0, 6, 11, 0); set_color(79, 6, 11, 0);
    set_color(0, 7, 11, 0); set_color(79, 7, 11, 0);
    set_color(0, 8, 11, 0); set_color(79, 8, 11, 0);
    set_color(0, 9, 11, 0); set_color(79, 9, 11, 0);
    color_text(0, 10, 80, 11);
    set_color(0, 11, 11, 0); set_color(79, 11, 11, 0);
    color_text(0, 12, 80, 11);

    print_str(2, 1, "VC TRACKER PLAYER   File:");
    color_text(2, 1, 26, 14);

    print_str(2, 2, "Status:");
    print_str(20, 2, "Order:");
    print_str(34, 2, "Row:");
    print_str(50, 2, "Time:");
    color_text(2, 2, 7, 7);
    color_text(20, 2, 6, 7);
    color_text(34, 2, 4, 7);
    color_text(50, 2, 5, 7);
    color_text(27, 2, 3, 15);
    color_text(39, 2, 3, 15);
    color_text(56, 2, 5, 15);
    print_char(58, 2, 58); set_color(58, 2, 15, 0);   // ':' между мм и сс - ставится один раз, не перерисовывается

    print_str(2, 5, "CH1"); color_text(2, 5, 3, 12);
    print_str(2, 6, "CH2"); color_text(2, 6, 3, 10);
    print_str(2, 7, "CH3"); color_text(2, 7, 3, 9);
    print_str(2, 8, "CH4"); color_text(2, 8, 3, 14);

    if (playlistMode == 1) {
        print_str(2, 11, "Ctrl+Q-exit  P-pause  Esc-list  <-prev  next->");
        color_text(2, 11, 46, 8);
    } else {
        print_str(2, 11, "Ctrl+Q - exit     P - pause / resume");
        color_text(2, 11, 37, 8);
    }

    // Метры каналов рисуются "пустыми" сразу здесь - основной цикл
    // (draw_channel()) потом только ДОРИСОВЫВАЕТ разницу с прошлым
    // кадром, начиная с lastFilled[ch]=0 (см. main()), а не всю полоску
    // целиком каждый раз.
    draw_empty_bar(5);
    draw_empty_bar(6);
    draw_empty_bar(7);
    draw_empty_bar(8);

    print_number3(BAR_X + BAR_LEN + 2, 5, 0); color_text(BAR_X + BAR_LEN + 2, 5, 3, 15);
    print_number3(BAR_X + BAR_LEN + 2, 6, 0); color_text(BAR_X + BAR_LEN + 2, 6, 3, 15);
    print_number3(BAR_X + BAR_LEN + 2, 7, 0); color_text(BAR_X + BAR_LEN + 2, 7, 3, 15);
    print_number3(BAR_X + BAR_LEN + 2, 8, 0); color_text(BAR_X + BAR_LEN + 2, 8, 3, 15);

    return 0;
}

// "Едущие блоки" - живой просмотр нот/сэмплов/эффектов ТЕКУЩЕГО играющего
// паттерна, "в духе" ProTracker (см. ASSEMBLY.md, "SoundCard"). Статика
// (рамка/заголовки/фон, включая подсветку центральной строки) - здесь,
// рисуется один раз вместе с draw_static(); содержимое обновляет
// отдельная draw_pattern_view() ниже, только когда меняется ROW.
//
// Курсор "текущая строка" ВСЕГДА на одном и том же месте экрана (слот
// PATTERN_CENTER, screenY = PATTERN_FIRST_ROW + PATTERN_CENTER) - едет
// не он, а содержимое вокруг (соседние строки паттерна), так что фон
// подсветки красится тут, один раз, и никогда не перекрашивается заново.
int draw_pattern_frame() {
    int x;
    int y;
    int ch;
    int bg;

    print_char(0, PATTERN_TOP, 204); print_char(79, PATTERN_TOP, 185);      // ╠ ╣
    x = 1; while (x < 79) { print_char(x, PATTERN_TOP, 205); x = x + 1; }   // ═

    print_char(0, PATTERN_BOTTOM, 200); print_char(79, PATTERN_BOTTOM, 188);   // ╚ ╝
    x = 1; while (x < 79) { print_char(x, PATTERN_BOTTOM, 205); x = x + 1; }

    color_text(0, PATTERN_TOP, 80, 11);
    color_text(0, PATTERN_BOTTOM, 80, 11);

    print_char(0, PATTERN_HEADER, 186); print_char(79, PATTERN_HEADER, 186);   // ║
    set_color(0, PATTERN_HEADER, 11, 0); set_color(79, PATTERN_HEADER, 11, 0);

    print_str(PATTERN_COL_X0, PATTERN_HEADER, "CH1");
    color_text(PATTERN_COL_X0, PATTERN_HEADER, 3, 12);
    print_str(PATTERN_COL_X0 + PATTERN_COL_WIDTH, PATTERN_HEADER, "CH2");
    color_text(PATTERN_COL_X0 + PATTERN_COL_WIDTH, PATTERN_HEADER, 3, 10);
    print_str(PATTERN_COL_X0 + PATTERN_COL_WIDTH * 2, PATTERN_HEADER, "CH3");
    color_text(PATTERN_COL_X0 + PATTERN_COL_WIDTH * 2, PATTERN_HEADER, 3, 9);
    print_str(PATTERN_COL_X0 + PATTERN_COL_WIDTH * 3, PATTERN_HEADER, "CH4");
    color_text(PATTERN_COL_X0 + PATTERN_COL_WIDTH * 3, PATTERN_HEADER, 3, 14);

    y = 0;
    while (y < PATTERN_ROWS) {
        bg = 0;
        if (y == PATTERN_CENTER) { bg = 4; }   // текущая строка - синий фон, фиксирован

        print_char(0, PATTERN_FIRST_ROW + y, 186);
        print_char(79, PATTERN_FIRST_ROW + y, 186);
        set_color(0, PATTERN_FIRST_ROW + y, 11, 0);
        set_color(79, PATTERN_FIRST_ROW + y, 11, 0);

        ch = 0;
        while (ch < 4) {
            x = PATTERN_COL_X0 + ch * PATTERN_COL_WIDTH;

            print_char(x + 3, PATTERN_FIRST_ROW + y, 32);   // пробелы-разделители - статичны
            print_char(x + 6, PATTERN_FIRST_ROW + y, 32);

            set_color(x, PATTERN_FIRST_ROW + y, 15, bg);       // нота - белым
            set_color(x + 1, PATTERN_FIRST_ROW + y, 15, bg);
            set_color(x + 2, PATTERN_FIRST_ROW + y, 15, bg);
            set_color(x + 3, PATTERN_FIRST_ROW + y, 7, bg);
            set_color(x + 4, PATTERN_FIRST_ROW + y, 11, bg);   // сэмпл - голубым
            set_color(x + 5, PATTERN_FIRST_ROW + y, 11, bg);
            set_color(x + 6, PATTERN_FIRST_ROW + y, 7, bg);
            set_color(x + 7, PATTERN_FIRST_ROW + y, 14, bg);   // эффект+параметр - жёлтым
            set_color(x + 8, PATTERN_FIRST_ROW + y, 14, bg);
            set_color(x + 9, PATTERN_FIRST_ROW + y, 14, bg);

            ch = ch + 1;
        }

        y = y + 1;
    }

    return 0;
}

// Обновляет ТОЛЬКО текст ячеек (не цвет/фон - см. draw_pattern_frame()
// выше) - зовётся из play_track_loop() при каждом изменении ROW, не
// каждый кадр. currentRow - ROW из SoundCard (0-63).
int draw_pattern_view(int currentRow) {
    int i;
    int ch;
    int temp;
    int targetRow;
    int valid;
    int screenY;
    int x;
    int note;
    int sample;
    int effect;
    int param;

    i = 0;
    while (i < PATTERN_ROWS) {
        // temp = currentRow + i, а не currentRow + i - PATTERN_CENTER
        // напрямую - int в мини-C беззнаковый (см. ASSEMBLY.md),
        // отрицательных промежуточных значений нет и быть не может.
        temp = currentRow + i;
        valid = 0;
        targetRow = 0;
        if (temp >= PATTERN_CENTER) {
            targetRow = temp - PATTERN_CENTER;
            if (targetRow <= 63) { valid = 1; }   // иначе уехали за конец паттерна
        }

        screenY = PATTERN_FIRST_ROW + i;

        ch = 0;
        while (ch < 4) {
            x = PATTERN_COL_X0 + ch * PATTERN_COL_WIDTH;

            if (valid == 1) {
                poke(SOUNDCARD_PATTERN_ROW_SELECT, targetRow);
                poke(SOUNDCARD_PATTERN_CHANNEL_SELECT, ch);
                note = peek(SOUNDCARD_PATTERN_NOTE);
                sample = peek(SOUNDCARD_PATTERN_SAMPLE);
                effect = peek(SOUNDCARD_PATTERN_EFFECT);
                param = peek(SOUNDCARD_PATTERN_PARAM);

                if (note == 255) {
                    print_str(x, screenY, "---");
                } else {
                    print_string(x, screenY, noteNames, note);
                }
                print_hex2(x + 4, screenY, sample);
                print_char(x + 7, screenY, hex_digit(effect));
                print_hex2(x + 8, screenY, param);
            } else {
                // Строка вне паттерна (уехали за начало/конец) - пусто.
                print_str(x, screenY, "   ");
                print_str(x + 4, screenY, "  ");
                print_char(x + 7, screenY, 32);
                print_str(x + 8, screenY, "  ");
            }

            ch = ch + 1;
        }

        i = i + 1;
    }

    return 0;
}

int print_arg_name(int x, int y, int len) {
    int i;
    i = 0;
    while (i < len) {
        print_char(x + i, y, cmdArgs[i]);
        i = i + 1;
    }
    color_text(x, y, len, 15);
    return 0;
}

int draw_status(int code) {
    // Печатает, только если статус реально изменился с прошлого кадра
    // (lastStatus). Поле фиксированной ширины 8 символов (col 10..17,
    // строка 2) - паддинг пробелами, иначе более короткое слово
    // оставляет "хвост" от предыдущего (например "PAUSED " после
    // "PLAYING ").
    if (code == lastStatus) { return 0; }
    lastStatus = code;

    if (code == 1) { print_str(10, 2, "PLAYING "); return 0; }
    if (code == 2) { print_str(10, 2, "PAUSED  "); return 0; }
    if (code == 3) { print_str(10, 2, "NO SONG "); return 0; }
    print_str(10, 2, "STOPPED ");
    return 0;
}

// Перерисовывает метр канала ch (0-3) КАК РАЗНИЦУ с прошлым кадром -
// трогает только те символы полоски, что реально сменили закрашенность
// (lastFilled[ch] -> filled), и число громкости только если оно
// изменилось (lastVol[ch]).
int draw_channel(int row, int vol, int color, int ch) {
    int filled;
    int x;
    int prevFilled;

    // filled = vol*BAR_LEN/64, но int в мини-C - 8 бит (0-255, см.
    // ASSEMBLY.md) и MUL реально переполняется молча выше 255 (та же
    // причина, по которой __mc_screen_offset считает y*80 циклом ADD, а
    // не одним MUL): vol*BAR_LEN доходит до 64*58=3712. BAR_LEN/64 =
    // 58/64 = 29/32 - тот же результат считается как vol - vol*3/32:
    // vol*3 максимум 192, безопасно помещается в байт.
    filled = vol - (vol * 3) / 32;
    prevFilled = lastFilled[ch];

    if (filled != prevFilled) {
        if (filled > prevFilled) {
            x = prevFilled;
            while (x < filled) {
                print_char(BAR_X + x, row, 219);   // █
                set_color(BAR_X + x, row, color, 0);
                x = x + 1;
            }
        } else {
            x = filled;
            while (x < prevFilled) {
                print_char(BAR_X + x, row, 176);   // ░
                set_color(BAR_X + x, row, 8, 0);
                x = x + 1;
            }
        }
        lastFilled[ch] = filled;
    }

    if (vol != lastVol[ch]) {
        print_number3(BAR_X + BAR_LEN + 2, row, vol);   // цвет уже белый - см. draw_static()
        lastVol[ch] = vol;
    }

    return 0;
}

int toggle_pause() {
    int st;
    st = peek(SOUNDCARD_STATUS);
    if (st == 1) { poke(SOUNDCARD_COMMAND, 3); return 0; }   // PLAYING -> PAUSE
    if (st == 2) { poke(SOUNDCARD_COMMAND, 4); return 0; }   // PAUSED -> RESUME
    return 0;
}

// Играет уже загруженный (ModLoader.LOAD уже сделан вызывающим кодом)
// трек до тех пор, пока пользователь не нажмёт что-то, что должно его
// остановить - возвращает, ЧТО делать дальше (см. ACTION_* выше).
// playlistMode=0 (запуск с именем файла параметром) - Esc/влево/вправо
// не активны вообще, только Ctrl+Q/P, как раньше; playlistMode=1 - все
// четыре, плюс без зацикливания на границах списка (стрелка молча
// ничего не делает, если ехать уже некуда - проверяется здесь, ДО
// остановки трека, поэтому играющий трек не прерывается впустую).
int play_track_loop(int playlistMode, int sel, int count) {
    int running;
    int key;
    int action;
    int order;
    int row;

    elapsedFrameTick = 0;
    elapsedSec = 0;
    elapsedMin = 0;
    draw_time();

    poke(SOUNDCARD_COMMAND, 1);   // PLAY

    running = 1;
    action = ACTION_EXIT;
    while (running == 1) {
        if ((peek(KEYBOARD_CONTROL) & 2) != 0) {
            key = peek(KEYBOARD_DATA);
            if (key == KEY_CTRL_Q) { running = 0; action = ACTION_EXIT; }
            if (key == KEY_P_UPPER) { toggle_pause(); }
            if (key == KEY_P_LOWER) { toggle_pause(); }
            if (playlistMode == 1) {
                if (key == KEY_ESC) { running = 0; action = ACTION_MENU; }
                if (key == KEY_LEFT) {
                    if (sel > 0) { running = 0; action = ACTION_PREV; }
                }
                if (key == KEY_RIGHT) {
                    if (sel < count - 1) { running = 0; action = ACTION_NEXT; }
                }
            }
        }

        draw_status(peek(SOUNDCARD_STATUS));

        order = peek(SOUNDCARD_ORDER_POS);
        if (order != lastOrder) { print_number3(27, 2, order); lastOrder = order; }
        row = peek(SOUNDCARD_ROW);
        if (row != lastRow) {
            print_number3(39, 2, row);
            lastRow = row;
            draw_pattern_view(row);
        }

        draw_channel(5, channelVol[0], 12, 0);
        draw_channel(6, channelVol[1], 10, 1);
        draw_channel(7, channelVol[2], 9, 2);
        draw_channel(8, channelVol[3], 14, 3);

        elapsedFrameTick = elapsedFrameTick + 1;
        if (elapsedFrameTick >= 30) {   // ~30 кадров по 33мс - см. elapsedFrameTick выше
            elapsedFrameTick = 0;
            elapsedSec = elapsedSec + 1;
            if (elapsedSec >= 60) { elapsedSec = 0; elapsedMin = elapsedMin + 1; }
            draw_time();
        }

        wait_ms(33);   // ~30 кадров/сек
    }

    poke(SOUNDCARD_COMMAND, 2);   // STOP

    return action;
}

// ---- Плейлист (PLAY.LST) ----

// Читает C/TOOLS/PLAY.LST (рядом с PLAYER.RUN) в playlist[][] - одна
// строка файла на один playlist[i]. Формат строки - "<ДИСК>/<путь от
// корня диска>" (см. заголовок файла); здесь путь не разбирается вообще,
// только режется на строки по LF (10) - разбор диска/пути происходит
// позже, в load_mod_from_playlist(), непосредственно перед загрузкой
// выбранного трека. CR (13) перед LF пропускается (см. EDIT.MC про
// формат Windows-переводов строк - тот же приём). Возвращает число
// прочитанных треков (0, если PLAY.LST не найден - тогда main() ведёт
// себя как раньше, без плейлиста).
int load_playlist() {
    int i;
    int count;
    int col;
    int ch;
    int done;

    // TOOLS всегда на диске C (0) - сам PLAY.LST не бывает
    // кросс-дисковым, кросс-дисковыми бывают только ТРЕКИ внутри него
    // (см. load_mod_from_playlist()). Сброс в корень диска C нужен
    // здесь, чтобы найти саму TOOLS независимо от того, откуда реально
    // запущен player (currentDir мог быть куда угодно смещён предыдущей
    // программой).
    i = 0;
    while (i < 16) { diskio_chdir_up(0); i = i + 1; }

    i = 0;
    while (i < 12) { diskio_set_name_char(0, i, 0); i = i + 1; }
    diskio_set_name_char(0, 0, 84);   // T
    diskio_set_name_char(0, 1, 79);   // O
    diskio_set_name_char(0, 2, 79);   // O
    diskio_set_name_char(0, 3, 76);   // L
    diskio_set_name_char(0, 4, 83);   // S
    diskio_chdir(0);

    i = 0;
    while (i < 12) { diskio_set_name_char(0, i, 0); i = i + 1; }
    diskio_set_name_char(0, 0, 80);   // P
    diskio_set_name_char(0, 1, 76);   // L
    diskio_set_name_char(0, 2, 65);   // A
    diskio_set_name_char(0, 3, 89);   // Y
    diskio_set_name_char(0, 4, 46);   // .
    diskio_set_name_char(0, 5, 76);   // L
    diskio_set_name_char(0, 6, 83);   // S
    diskio_set_name_char(0, 7, 84);   // T

    diskio_cmd(0, DISKIO_OPEN_READ);
    if (diskio_status(0) == 2) { return 0; }   // PLAY.LST не найден

    count = 0;
    col = 0;
    done = 0;
    while (done == 0) {
        diskio_cmd(0, DISKIO_READ_BYTE);
        if (diskio_status(0) == 1) {
            done = 1;   // EOF
        } else {
            ch = diskio_data(0);
            if (ch == 13) {
                // CR перед LF - игнорируем, конец строки только по LF
            } else {
                if (ch == 10) {
                    if (col > 0) {
                        playlist[count][col] = 0;
                        count = count + 1;
                        col = 0;
                        if (count >= PLAYLIST_MAX) { done = 1; }
                    }
                } else {
                    if (col < PLAYLIST_WIDTH - 1) {
                        playlist[count][col] = ch;
                        col = col + 1;
                    }
                }
            }
        }
    }

    // Последняя строка файла без завершающего LF (EOF сразу после
    // текста) - без этого она тихо терялась бы.
    if (col > 0) {
        if (count < PLAYLIST_MAX) {
            playlist[count][col] = 0;
            count = count + 1;
        }
    }

    diskio_cmd(0, DISKIO_CLOSE);

    return count;
}

int draw_playlist_frame() {
    int x;

    clear_screen();

    print_char(0, 0, 201); print_char(79, 0, 187);   // ╔ ╗
    x = 1; while (x < 79) { print_char(x, 0, 205); x = x + 1; }   // ═

    print_char(0, 2, 204); print_char(79, 2, 185);   // ╠ ╣
    x = 1; while (x < 79) { print_char(x, 2, 205); x = x + 1; }

    print_char(0, 3 + PLAYLIST_MAX, 200); print_char(79, 3 + PLAYLIST_MAX, 188);   // ╚ ╝
    x = 1; while (x < 79) { print_char(x, 3 + PLAYLIST_MAX, 205); x = x + 1; }

    print_char(0, 1, 186); print_char(79, 1, 186);   // ║
    x = 3;
    while (x < 3 + PLAYLIST_MAX) { print_char(0, x, 186); print_char(79, x, 186); x = x + 1; }

    color_text(0, 0, 80, 11);
    set_color(0, 1, 11, 0); set_color(79, 1, 11, 0);
    color_text(0, 2, 80, 11);
    x = 3;
    while (x < 3 + PLAYLIST_MAX) { set_color(0, x, 11, 0); set_color(79, x, 11, 0); x = x + 1; }
    color_text(0, 3 + PLAYLIST_MAX, 80, 11);

    print_str(2, 1, "VC TRACKER PLAYER - Playlist");
    color_text(2, 1, 29, 14);

    print_str(0, 3 + PLAYLIST_MAX + 2, "^/v-move   Enter-play   Ctrl+Q-exit");
    x = 0;
    while (x < 80) { set_color(x, 3 + PLAYLIST_MAX + 2, 0, 7); x = x + 1; }

    return 0;
}

int render_playlist(int count, int sel) {
    int entryIdx;
    int color;

    entryIdx = 0;
    while (entryIdx < count) {
        print_string(4, 3 + entryIdx, playlist, entryIdx);
        color = 15;
        if (entryIdx == sel) { color = 10; }
        color_text(4, 3 + entryIdx, PLAYLIST_WIDTH - 2, color);
        entryIdx = entryIdx + 1;
    }

    return 0;
}

// Показывает список плейлиста, ждёт Enter/стрелки/Ctrl+Q. Возвращает
// выбранный индекс (0..count-1), либо count - сентинел "нажали Ctrl+Q,
// ничего не выбрано" (обычный int, отрицательных литералов в мини-C
// нет - см. ASSEMBLY.md - а count всегда вне диапазона реальных
// индексов 0..count-1).
int run_playlist_menu(int count) {
    int sel;
    int key;
    int running;

    sel = 0;
    draw_playlist_frame();
    render_playlist(count, sel);

    running = 1;
    while (running == 1) {
        if ((peek(KEYBOARD_CONTROL) & 2) != 0) {
            key = peek(KEYBOARD_DATA);
            if (key == KEY_CTRL_Q) { return count; }
            if (key == KEY_ENTER) { return sel; }
            if (key == KEY_UP) {
                if (sel > 0) { sel = sel - 1; render_playlist(count, sel); }
            }
            if (key == KEY_DOWN) {
                if (sel < count - 1) { sel = sel + 1; render_playlist(count, sel); }
            }
        }
    }

    return sel;
}

// Разбирает playlist[sel] ("<ДИСК>/<путь>"), выбирает диск в ModLoader
// (см. MODLOADER_DISK_SELECT/ModLoaderDiskSelect.h), сбрасывает
// currentDir ВЫБРАННОГО диска в корень (путь в playlist - от корня
// диска, а не от текущей папки - см. заголовок файла) и грузит трек.
// Возвращает STATUS ModLoader, как и load_mod_from_arg().
int load_mod_from_playlist(int sel) {
    int letter;
    int diskSel;
    int i;
    int j;
    int ch;

    letter = playlist[sel][0];
    diskSel = 1;                       // диск C по умолчанию
    if (letter == 68) { diskSel = 2; } // 'D'
    poke(MODLOADER_DISK_SELECT, diskSel);

    // diskSel-1 переводит соглашение ModLoader (1=C,2=D) в соглашение
    // DISKIO.MC (0=C,1=D) - только тут, больше нигде эти два числа не
    // пересекаются.
    i = 0;
    while (i < 16) { diskio_chdir_up(diskSel - 1); i = i + 1; }

    // Копируем playlist[sel] начиная с индекса 2 (пропускаем "C/"/"D/")
    // в NAME-буфер ModLoader - тот же приём, что load_mod_from_arg()
    // делает с cmdArgs.
    i = 0; j = 2;
    while (i < 32) {
        ch = playlist[sel][j];
        modName[i] = ch;
        if (ch != 0) { j = j + 1; }
        i = i + 1;
    }

    poke(MODLOADER_COMMAND, 1);   // LOAD
    return peek(MODLOADER_STATUS);
}

int main() {
    int argLen;
    int status;
    int count;
    int sel;
    int action;
    int menuRunning;

    init_note_names();

    argLen = peek(CMD_ARGS_LEN);
    if (argLen > 16) { argLen = 16; }   // ширина cmdArgs - см. заголовок файла

    if (argLen == 0) {
        // Без аргумента - режим плейлиста (см. заголовок файла).
        // Отсутствующий PLAY.LST - тот же "Usage:", что и раньше (для
        // тех, кто просто набрал "player" без параметра и без плейлиста).
        count = load_playlist();
        if (count == 0) {
            clear_screen();
            print_str(0, 0, "Usage: player FILENAME.MOD");
            wait_key();
            return 1;
        }

        sel = 0;
        action = ACTION_MENU;   // первый заход - всегда показать список
        menuRunning = 1;
        while (menuRunning == 1) {
            if (action == ACTION_MENU) {
                sel = run_playlist_menu(count);
                if (sel >= count) { return 0; }   // Ctrl+Q в меню - выход
            } else {
                // ACTION_NEXT/ACTION_PREV - play_track_loop() уже
                // проверил границы списка (см. его комментарий), сюда
                // попадаем только с валидным следующим/предыдущим sel.
                if (action == ACTION_NEXT) { sel = sel + 1; }
                if (action == ACTION_PREV) { sel = sel - 1; }
            }

            status = load_mod_from_playlist(sel);
            if (status != 0) {
                clear_screen();
                if (status == 1) { print_str(0, 0, "MOD file not found"); }
                else {
                    if (status == 2) { print_str(0, 0, "Unsupported MOD format"); }
                    else { print_str(0, 0, "MOD file is corrupt"); }
                }
                wait_key();
                action = ACTION_MENU;   // назад к списку
            } else {
                reset_delta_state();
                draw_static(1);
                draw_pattern_frame();
                print_string(29, 1, playlist, sel);
                action = play_track_loop(1, sel, count);
                if (action == ACTION_EXIT) { menuRunning = 0; }
                // ACTION_MENU/ACTION_NEXT/ACTION_PREV - следующая
                // итерация while обработает их сама.
            }
        }

        return 0;
    }

    status = load_mod_from_arg(argLen);
    if (status != 0) {
        clear_screen();
        if (status == 1) { print_str(0, 0, "MOD file not found"); }
        else {
            if (status == 2) { print_str(0, 0, "Unsupported MOD format"); }
            else { print_str(0, 0, "MOD file is corrupt"); }
        }
        wait_key();
        return 1;
    }

    reset_delta_state();
    draw_static(0);
    draw_pattern_frame();
    print_arg_name(29, 1, argLen);
    play_track_loop(0, 0, 1);   // playlistMode=0 - Esc/влево/вправо не активны, sel/count не используются

    return 0;
}
