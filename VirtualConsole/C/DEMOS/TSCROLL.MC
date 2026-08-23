// TSCROLL.MC - тайловая карта с плавным скроллингом по стрелкам, на
// мини-C (см. ASSEMBLY.md, "Мини-C"). Портирует C/DEMOS/TILEDEMO.ASM с
// автоматического блуждания на управление игроком, но использует те же
// ресурсы (TILES.PNG, SPRITES.PNG, MAP.TXT) и те же регистры устройств.
//
// Адреса регистров Keyboard/Clock/VideoCard/PngLoader/MapLoader (KEYBOARD_*/
// CLOCK_*/VIDEOCARD_*/PNGLOADER_*/MAPLOADER_*) и готовые NAME-буферы
// pngLoaderName/mapLoaderName объявлять не нужно - компилятор сам подмешивает
// их перед любой Mini-C программой. Запись имени файла - одной строкой через
// str_copy(), а не байт-в-байт.
//
// Управление - toggle-направление, а не "пока зажато": стрелка задаёт
// направление и запускает НЕПРЕРЫВНЫЙ скролл с фиксированной скоростью
// каждый кадр, пока не придёт другая команда. Это специально сделано так,
// а не "двигаться, пока физически зажата клавиша" - у Keyboard::tick()
// стрелки приходят как отдельные события на repeat-rate ОС (с начальной
// задержкой перед повтором), а не на частоту кадров, так что "зажатие"
// дало бы рывками неровный скролл. Повторное нажатие ТОЙ ЖЕ стрелки или
// пробел (32) - останавливает; другая стрелка - меняет направление; упор
// в край карты - тоже останавливает (в отличие от TILEDEMO.ASM, тут новое
// направление не выбирается само - решает игрок). Ctrl+Q - выход.
//
// Раньше здесь было ограничение "стрелки работают только в фокусе
// консольного окна, не окна VideoCard" - актуально для истории, но не
// для текущего кода: VideoCard больше не открывает своё окно вообще
// (см. VideoCard.h) - единственное окно у VideoConsole, и оно ловит
// WM_KEYDOWN для стрелок/F-клавиш (см. VideoConsole.cpp), поэтому
// управление работает в фокусе того же окна, где видна графика.
//
// Собирается командой "build tscroll.mc", запускается как "tscroll".

// клэмп скролла - та же карта 40x30 тайлов по 32px (1280x960), что и в
// TILEDEMO.ASM, экран 320x240: maxScrollX = 1280-320 = 960, maxScrollY =
// 960-240 = 720.
const MAX_SCROLL_X_HIGH = 3;
const MAX_SCROLL_X_LOW  = 192;   // 960 = 3*256+192
const MAX_SCROLL_Y_HIGH = 2;
const MAX_SCROLL_Y_LOW  = 208;   // 720 = 2*256+208

const SCROLL_SPEED = 2;   // px/кадр - фиксированная скорость плавного скролла

const KEY_UP    = 72;   // стрелка вверх (extended-код _getch(), см. FM.MC)
const KEY_DOWN  = 80;   // стрелка вниз
const KEY_LEFT  = 75;   // стрелка влево (та же extended-таблица, что UP/DOWN)
const KEY_RIGHT = 77;   // стрелка вправо
const KEY_SPACE = 32;
const KEY_CTRL_Q = 17;

const DIR_UP    = 0;
const DIR_DOWN  = 1;
const DIR_LEFT  = 2;
const DIR_RIGHT = 3;
const DIR_NONE  = 4;

int scrollXLow;
int scrollXHigh;
int scrollYLow;
int scrollYHigh;
int dirCode;
int moving;
int running;

int wait_ms(int ms) {
    poke(CLOCK_LOW, 0);
    while (peek(CLOCK_LOW) < ms) {
    }
    return 0;
}

// ---- лоадер тайлов: загрузка PNG-файла в PngLoader по имени ----

int load_tileset() {
    str_copy(pngLoaderName, "TILES.PNG");
    poke(PNGLOADER_COMMAND, 1);   // LOAD
    return peek(PNGLOADER_STATUS);
}

int load_spriteset() {
    str_copy(pngLoaderName, "SPRITES.PNG");
    poke(PNGLOADER_COMMAND, 1);   // LOAD
    return peek(PNGLOADER_STATUS);
}

// Вырезает один тайл из уже загруженного тайлсета в TILE_INDEX (0-7).
// srcX/srcY - 16-битные координаты на TILES.PNG как пары low/high байт
// (см. ASSEMBLY.md, "PngLoader" - те же исходные координаты, что и в
// TILEDEMO.ASM, extract_tile0..7).
int extract_tile(int srcXLow, int srcXHigh, int srcYLow, int srcYHigh, int tileIndex) {
    poke(PNGLOADER_SRC_X_LOW, srcXLow);
    poke(PNGLOADER_SRC_X_HIGH, srcXHigh);
    poke(PNGLOADER_SRC_Y_LOW, srcYLow);
    poke(PNGLOADER_SRC_Y_HIGH, srcYHigh);
    poke(PNGLOADER_TILE_INDEX, tileIndex);
    poke(PNGLOADER_COMMAND, 3);   // EXTRACT_TILE
    return 0;
}

int extract_all_tiles() {
    extract_tile(0, 0, 0, 0, 0);
    extract_tile(0, 0, 64, 0, 1);
    extract_tile(32, 0, 64, 0, 2);
    extract_tile(32, 0, 192, 0, 3);
    extract_tile(32, 0, 0, 1, 4);     // srcY = 256
    extract_tile(96, 0, 96, 1, 5);    // srcY = 352
    extract_tile(0, 0, 128, 1, 6);    // srcY = 384
    extract_tile(0, 0, 160, 1, 7);    // srcY = 416
    return 0;
}

// ---- лоадер карты ----

int load_map() {
    str_copy(mapLoaderName, "MAP.TXT");
    poke(MAPLOADER_COMMAND, 1);   // LOAD
    return peek(MAPLOADER_STATUS);
}

// ---- спрайт персонажа: грузится отдельно от тайлсета, ставится в центр ----

int place_player_sprite() {
    poke(PNGLOADER_SRC_X_LOW, 0);
    poke(PNGLOADER_SRC_X_HIGH, 0);
    poke(PNGLOADER_SRC_Y_LOW, 0);
    poke(PNGLOADER_SRC_Y_HIGH, 0);
    poke(PNGLOADER_SPRITE_INDEX, 0);
    poke(PNGLOADER_COMMAND, 2);   // EXTRACT

    poke(VIDEOCARD_SPRITE_INDEX, 0);
    poke(VIDEOCARD_SPRITE_X_LOW, 144);   // (320-32)/2
    poke(VIDEOCARD_SPRITE_X_HIGH, 0);
    poke(VIDEOCARD_SPRITE_Y_LOW, 104);   // (240-32)/2
    poke(VIDEOCARD_SPRITE_Y_HIGH, 0);
    poke(VIDEOCARD_SPRITE_VISIBLE, 1);
    return 0;
}

// ---- скролл: пары low/high байт с ручным переносом (мини-C заворачивает
// 8-битное переполнение сам - см. ASSEMBLY.md - поэтому перенос детектим
// по == 0 после +1 / == 255 после -1, как SBC/ADC в TILEDEMO.ASM) ----

int apply_scroll() {
    poke(VIDEOCARD_SCROLL_X_LOW, scrollXLow);
    poke(VIDEOCARD_SCROLL_X_HIGH, scrollXHigh);
    poke(VIDEOCARD_SCROLL_Y_LOW, scrollYLow);
    poke(VIDEOCARD_SCROLL_Y_HIGH, scrollYHigh);
    return 0;
}

int try_move_up() {
    int i;
    if (scrollYHigh == 0) {
        if (scrollYLow == 0) { moving = 0; return 0; }
    }
    i = 0;
    while (i < SCROLL_SPEED) {
        if (scrollYHigh == 0) {
            if (scrollYLow == 0) { moving = 0; i = SCROLL_SPEED; }
        }
        if (i < SCROLL_SPEED) {
            scrollYLow = scrollYLow - 1;
            if (scrollYLow == 255) { scrollYHigh = scrollYHigh - 1; }
            i = i + 1;
        }
    }
    return 0;
}

int try_move_down() {
    int i;
    int atMax;
    i = 0;
    while (i < SCROLL_SPEED) {
        atMax = 0;
        if (scrollYHigh > MAX_SCROLL_Y_HIGH) { atMax = 1; }
        if (scrollYHigh == MAX_SCROLL_Y_HIGH) {
            if (scrollYLow >= MAX_SCROLL_Y_LOW) { atMax = 1; }
        }
        if (atMax == 1) {
            moving = 0;
            i = SCROLL_SPEED;
        } else {
            scrollYLow = scrollYLow + 1;
            if (scrollYLow == 0) { scrollYHigh = scrollYHigh + 1; }
            i = i + 1;
        }
    }
    return 0;
}

int try_move_left() {
    int i;
    if (scrollXHigh == 0) {
        if (scrollXLow == 0) { moving = 0; return 0; }
    }
    i = 0;
    while (i < SCROLL_SPEED) {
        if (scrollXHigh == 0) {
            if (scrollXLow == 0) { moving = 0; i = SCROLL_SPEED; }
        }
        if (i < SCROLL_SPEED) {
            scrollXLow = scrollXLow - 1;
            if (scrollXLow == 255) { scrollXHigh = scrollXHigh - 1; }
            i = i + 1;
        }
    }
    return 0;
}

int try_move_right() {
    int i;
    int atMax;
    i = 0;
    while (i < SCROLL_SPEED) {
        atMax = 0;
        if (scrollXHigh > MAX_SCROLL_X_HIGH) { atMax = 1; }
        if (scrollXHigh == MAX_SCROLL_X_HIGH) {
            if (scrollXLow >= MAX_SCROLL_X_LOW) { atMax = 1; }
        }
        if (atMax == 1) {
            moving = 0;
            i = SCROLL_SPEED;
        } else {
            scrollXLow = scrollXLow + 1;
            if (scrollXLow == 0) { scrollXHigh = scrollXHigh + 1; }
            i = i + 1;
        }
    }
    return 0;
}

// ---- ввод со стрелок (toggle-направление, см. комментарий в начале файла) ----

int handle_input() {
    int key;
    key = peek(KEYBOARD_DATA);

    if (key == KEY_CTRL_Q) { running = 0; return 0; }
    if (key == KEY_SPACE) { moving = 0; return 0; }

    if (key == KEY_UP) {
        if (dirCode == DIR_UP) { moving = 0; } else { dirCode = DIR_UP; moving = 1; }
        return 0;
    }
    if (key == KEY_DOWN) {
        if (dirCode == DIR_DOWN) { moving = 0; } else { dirCode = DIR_DOWN; moving = 1; }
        return 0;
    }
    if (key == KEY_LEFT) {
        if (dirCode == DIR_LEFT) { moving = 0; } else { dirCode = DIR_LEFT; moving = 1; }
        return 0;
    }
    if (key == KEY_RIGHT) {
        if (dirCode == DIR_RIGHT) { moving = 0; } else { dirCode = DIR_RIGHT; moving = 1; }
        return 0;
    }
    return 0;
}

int main() {
    int status;

    status = load_tileset();
    if (status != 0) {
        clear_screen();
        print_str(0, 0, "tileset load error");
        return 1;
    }
    extract_all_tiles();

    status = load_map();
    if (status != 0) {
        clear_screen();
        print_str(0, 0, "map load error");
        return 1;
    }

    status = load_spriteset();
    if (status != 0) {
        clear_screen();
        print_str(0, 0, "sprite load error");
        return 1;
    }
    place_player_sprite();

    poke(VIDEOCARD_COMMAND, 1);   // MODE_ON

    scrollXLow = 0;
    scrollXHigh = 0;
    scrollYLow = 0;
    scrollYHigh = 0;
    dirCode = DIR_NONE;
    moving = 0;
    running = 1;

    while (running == 1) {
        handle_input();

        if (moving == 1) {
            if (dirCode == DIR_UP) { try_move_up(); }
            if (dirCode == DIR_DOWN) { try_move_down(); }
            if (dirCode == DIR_LEFT) { try_move_left(); }
            if (dirCode == DIR_RIGHT) { try_move_right(); }
            apply_scroll();
        }

        wait_ms(17);   // ~60 кадров/сек
    }

    poke(VIDEOCARD_COMMAND, 2);   // MODE_OFF

    return 0;
}
