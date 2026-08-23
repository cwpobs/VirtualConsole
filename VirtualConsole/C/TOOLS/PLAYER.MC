// PLAYER.MC - проигрыватель трекерной музыки (.mod) с живым
// визуализатором в текстовом псевдографическом режиме, "в духе"
// Impulse Tracker: рамка, статус/Order/Row и четыре горизонтальных
// VU-метра, по одному на канал ProTracker (данные - из read-only
// регистров визуализации SoundCard: CHANNEL0-3_VOLUME/ROW/ORDER_POS,
// см. ASSEMBLY.md, "SoundCard"). Выбор трека/плейлисты - в следующих
// итерациях (см. заголовок задачи); v1 - один файл на запуск.
//
// Имя .mod передаётся параметром командной строки (см. ASSEMBLY.md,
// "Аргументы командной строки"):
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
// mod_load() из Мини-C принимает только строковый ЛИТЕРАЛ, известный на
// этапе компиляции (см. ASSEMBLY.md, "Звук и музыка: mod_load()/
// sound_*()") - для рантайм-имени (наш случай, имя приходит параметром)
// программа сама копирует байты cmdArgs в NAME-буфер ModLoader
// (0xF0001020-0xF000103F, маппированный массив modName[32]) и вручную
// триггерит COMMAND=LOAD - тот же приём, что MUSIC.ASM когда-то делал
// руками на голом ассемблере, но для одного зашитого имени.
//
// Управление: Ctrl+Q - остановить и выйти, P - пауза/продолжить.
//
// Собирается командой "build player.mc", запускается как
// "player ИМЯ.MOD".

#include "STRLIB.MC"

const MODLOADER_COMMAND = 0xF0001040;
const MODLOADER_STATUS  = 0xF0001041;

const SOUNDCARD_COMMAND    = 0xF0001066;
const SOUNDCARD_STATUS     = 0xF0001067;
const SOUNDCARD_ROW        = 0xF000106D;
const SOUNDCARD_ORDER_POS  = 0xF000106E;

const KEY_CTRL_Q  = 17;
const KEY_P_UPPER = 80;
const KEY_P_LOWER = 112;

const BAR_X   = 9;
const BAR_LEN = 58;   // ширина шкалы под громкость канала 0-64

int modName[32] = 0xF0001020;      // NAME0-31 у ModLoader
int channelVol[4] = 0xF0001069;    // CHANNEL0-3_VOLUME у SoundCard (read-only)

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
    int i;
    i = 0;
    while (i < len) {
        set_color(x + i, y, fg, 0);
        i = i + 1;
    }
    return 0;
}

// Статическая часть экрана (рамка/подписи) - рисуется один раз, дальше
// каждый кадр обновляются только цифры/метры поверх неё (см. main()).
int draw_static() {
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

    color_text(0, 0, 80, 11);
    color_text(0, 1, 80, 11);
    color_text(0, 2, 80, 11);
    color_text(0, 3, 80, 11);
    color_text(0, 4, 80, 11);
    color_text(0, 5, 80, 11);
    color_text(0, 6, 80, 11);
    color_text(0, 7, 80, 11);
    color_text(0, 8, 80, 11);
    color_text(0, 9, 80, 11);
    color_text(0, 10, 80, 11);
    color_text(0, 11, 80, 11);
    color_text(0, 12, 80, 11);

    print_str(2, 1, "VC TRACKER PLAYER   File:");
    color_text(2, 1, 26, 14);

    print_str(2, 2, "Status:");
    print_str(20, 2, "Order:");
    print_str(34, 2, "Row:");
    color_text(2, 2, 7, 7);
    color_text(20, 2, 6, 7);
    color_text(34, 2, 4, 7);

    print_str(2, 5, "CH1"); color_text(2, 5, 3, 12);
    print_str(2, 6, "CH2"); color_text(2, 6, 3, 10);
    print_str(2, 7, "CH3"); color_text(2, 7, 3, 9);
    print_str(2, 8, "CH4"); color_text(2, 8, 3, 14);

    print_str(2, 11, "Ctrl+Q - exit     P - pause / resume");
    color_text(2, 11, 37, 8);

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
    // Фиксированное поле шириной 8 символов (col 10..17, строка 2) -
    // паддинг пробелами, иначе более короткое слово оставляет "хвост"
    // от предыдущего (например "PAUSED " после "PLAYING ").
    if (code == 1) { print_str(10, 2, "PLAYING "); return 0; }
    if (code == 2) { print_str(10, 2, "PAUSED  "); return 0; }
    if (code == 3) { print_str(10, 2, "NO SONG "); return 0; }
    print_str(10, 2, "STOPPED ");
    return 0;
}

int draw_channel(int row, int vol, int color) {
    int filled;
    int x;

    filled = vol * BAR_LEN / 64;

    x = 0;
    while (x < BAR_LEN) {
        if (x < filled) {
            print_char(BAR_X + x, row, 219);   // █
            set_color(BAR_X + x, row, color, 0);
        } else {
            print_char(BAR_X + x, row, 176);   // ░
            set_color(BAR_X + x, row, 8, 0);
        }
        x = x + 1;
    }

    print_number3(BAR_X + BAR_LEN + 2, row, vol);
    color_text(BAR_X + BAR_LEN + 2, row, 3, 15);

    return 0;
}

int toggle_pause() {
    int st;
    st = peek(SOUNDCARD_STATUS);
    if (st == 1) { poke(SOUNDCARD_COMMAND, 3); return 0; }   // PLAYING -> PAUSE
    if (st == 2) { poke(SOUNDCARD_COMMAND, 4); return 0; }   // PAUSED -> RESUME
    return 0;
}

int main() {
    int argLen;
    int status;
    int running;
    int key;

    argLen = peek(CMD_ARGS_LEN);
    if (argLen > 16) { argLen = 16; }   // ширина cmdArgs - см. заголовок файла

    if (argLen == 0) {
        clear_screen();
        print_str(0, 0, "Usage: player FILENAME.MOD");
        wait_key();
        return 1;
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

    draw_static();
    print_arg_name(29, 1, argLen);

    poke(SOUNDCARD_COMMAND, 1);   // PLAY

    running = 1;
    while (running == 1) {
        if ((peek(KEYBOARD_CONTROL) & 2) != 0) {
            key = peek(KEYBOARD_DATA);
            if (key == KEY_CTRL_Q) { running = 0; }
            if (key == KEY_P_UPPER) { toggle_pause(); }
            if (key == KEY_P_LOWER) { toggle_pause(); }
        }

        draw_status(peek(SOUNDCARD_STATUS));
        print_number3(27, 2, peek(SOUNDCARD_ORDER_POS));
        print_number3(39, 2, peek(SOUNDCARD_ROW));
        color_text(27, 2, 3, 15);
        color_text(39, 2, 3, 15);

        draw_channel(5, channelVol[0], 12);
        draw_channel(6, channelVol[1], 10);
        draw_channel(7, channelVol[2], 9);
        draw_channel(8, channelVol[3], 14);

        wait_ms(33);   // ~30 кадров/сек, тот же приём, что MUSIC2.MC
    }

    poke(SOUNDCARD_COMMAND, 2);   // STOP

    return 0;
}
