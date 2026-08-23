// SNOW3D.MC - демо "комбинированного режима" (см. ConsoleLayer.h,
// CONSOLE_VISIBLE): тайловая карта плавно скроллится туда-сюда,
// статичный спрайт сидит в углу, крутится цветной 3D-куб (Gpu3D) - и
// одновременно, поверх всего этого, консоль медленно, в случайном
// порядке, заполняется разноцветными "снежинками". Показывает, что
// текст и графика теперь могут быть видны ОДНОВременно в одном окне:
// MODE_ON сам прячет консоль (см. VideoCard::modeOn), но эта демка
// явно включает её обратно через poke(CONSOLE_VISIBLE, 1) и продолжает
// печатать текст, пока графика крутится.
//
// Тайлы/карта/спрайт - те же ресурсы, что у C/DEMOS/TSCROLL.MC/
// TILEDEMO.ASM (TILES.PNG/MAP.TXT/SPRITES.PNG), куб - тот же, что у
// C/DEMOS/CUBE3D.ASM (8 вершин ±30, 12 треугольников, вращение по
// YAW), только вершины/треугольники собраны через мини-C функции
// tri()/emit() вместо развёрнутого ассемблерного кода.
//
// "Снежинка" - символ '*' случайным цветом из 6 ярких, фон - BG_TRANSPARENT
// (см. TextAttr.h, TRANSPARENT_BG): рисуется только сама звёздочка, фон
// ячейки не закрашивается - под ней остаётся видна графика (тайлы/куб),
// а не чёрный прямоугольник вокруг каждой снежинки. print_char/set_color
// (те же встроенные функции мини-C, что и везде) пишут в TextVRAM/TextAttr
// в любой момент, независимо от того, видна консоль прямо сейчас или нет -
// CONSOLE_VISIBLE решает только рисовать ли то, что уже накоплено (см.
// VideoConsole.h).
//
// Порядок ячеек - НЕ линейный конгруэнтный генератор по всей сетке:
// при 8-битном int (см. ASSEMBLY.md, "Мини-C") у такого генератора
// период всего 256 - на сетке 80x25=2000 ячеек он начал бы повторять
// один и тот же короткий узор из ~85 ячеек каждые несколько секунд
// вместо честного заполнения всего экрана (проверено вживую - именно
// так и произошло на первой версии этого файла). Вместо этого - два
// НЕЗАВИСИМЫХ обхода взаимно простым шагом (7 и с 80, и с 25 - см.
// COL_STEP/ROW_STEP): внутри одной строки шаг 7 по modulo 80
// гарантированно проходит все 80 колонок ровно по разу, не повторяясь
// (взаимно простые числа), затем переход на следующую строку тем же
// приёмом по modulo 25 - в сумме ровно 2000 ячеек без повторов за
// полный проход. Cам символ каждой ячейки - обычный '*', а вот ЦВЕТ
// каждой снежинки уже берётся из простого линейного конгруэнтного
// генератора (a=5, c=1, полный период 256) - для цвета короткий
// период не проблема, глаз не отслеживает точный порядок повторов
// раскраски так, как отслеживает повтор положения.
//
// Ctrl+Q - выход (сразу, не дожидаясь конца анимации).
//
// Собирается командой "build snow3d.mc", запускается как "snow3d".

const KEY_CTRL_Q = 17;

const BG_TRANSPARENT = 8;   // см. TextAttr::TRANSPARENT_BG

const SCROLL_SPEED = 2;   // px/кадр, как в TSCROLL.MC

// та же карта 40x30 тайлов по 32px (1280x960), что и в TILEDEMO.ASM/
// TSCROLL.MC, экран 320x240: maxScrollX = 1280-320 = 960
const MAX_SCROLL_X_HIGH = 3;
const MAX_SCROLL_X_LOW  = 192;   // 960 = 3*256+192

// Gpu3D - адреса не подмешиваются компилятором (см. Compiler.cpp,
// kDevicePrelude - там только Keyboard/Clock/VideoCard/ConsoleLayer/
// PngLoader/MapLoader), объявляем как в C/DEMOS/CUBE3D.ASM.
const GPU3D_VX_LOW = 0xF0001045;
const GPU3D_VX_HIGH = 0xF0001046;
const GPU3D_VY_LOW = 0xF0001047;
const GPU3D_VY_HIGH = 0xF0001048;
const GPU3D_VZ_LOW = 0xF0001049;
const GPU3D_VZ_HIGH = 0xF000104A;
const GPU3D_VR = 0xF000104B;
const GPU3D_VG = 0xF000104C;
const GPU3D_VB = 0xF000104D;
const GPU3D_COMMAND = 0xF000104E;
const GPU3D_OBJ_YAW_LOW = 0xF0001056;
const GPU3D_OBJ_YAW_HIGH = 0xF0001057;
const GPU3D_CAM_Z_LOW = 0xF0001060;
const GPU3D_CAM_Z_HIGH = 0xF0001061;

const COL_STEP = 7;   // gcd(7,80)=1 - полный обход 80 колонок без повторов
const ROW_STEP = 7;   // gcd(7,25)=1 - полный обход 25 строк без повторов

int scrollXLow;
int scrollXHigh;
int scrollDir;   // 0 = вправо, 1 = влево

int yawLow;
int yawHigh;

int rng;
int frameCount;
int running;

int snowCol;
int snowRow;
int snowColStep;   // сколько колонок пройдено в текущей строке (0-79)

int wait_ms(int ms) {
    poke(CLOCK_LOW, 0);
    while (peek(CLOCK_LOW) < ms) {
    }
    return 0;
}

// ---- загрузка ресурсов (тайлы/карта/спрайт - как в TSCROLL.MC) ----

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
    extract_tile(32, 0, 0, 1, 4);
    extract_tile(96, 0, 96, 1, 5);
    extract_tile(0, 0, 128, 1, 6);
    extract_tile(0, 0, 160, 1, 7);
    return 0;
}

int load_map() {
    str_copy(mapLoaderName, "MAP.TXT");
    poke(MAPLOADER_COMMAND, 1);   // LOAD
    return peek(MAPLOADER_STATUS);
}

// Один статичный спрайт в верхнем левом углу - просто иконка первого
// кадра спрайтшита, никуда не двигается (см. заголовок файла).
int place_corner_sprite() {
    poke(PNGLOADER_SRC_X_LOW, 0);
    poke(PNGLOADER_SRC_X_HIGH, 0);
    poke(PNGLOADER_SRC_Y_LOW, 0);
    poke(PNGLOADER_SRC_Y_HIGH, 0);
    poke(PNGLOADER_SPRITE_INDEX, 0);
    poke(PNGLOADER_COMMAND, 2);   // EXTRACT

    poke(VIDEOCARD_SPRITE_INDEX, 0);
    poke(VIDEOCARD_SPRITE_X_LOW, 4);
    poke(VIDEOCARD_SPRITE_X_HIGH, 0);
    poke(VIDEOCARD_SPRITE_Y_LOW, 4);
    poke(VIDEOCARD_SPRITE_Y_HIGH, 0);
    poke(VIDEOCARD_SPRITE_VISIBLE, 1);
    return 0;
}

// ---- скролл карты туда-сюда (тот же приём ручного переноса low/high,
// что в TSCROLL.MC/TILEDEMO.ASM - мини-C 8-битный int заворачивает
// переполнение сам, перенос в high byte детектим по 0/255) ----

int apply_scroll() {
    poke(VIDEOCARD_SCROLL_X_LOW, scrollXLow);
    poke(VIDEOCARD_SCROLL_X_HIGH, scrollXHigh);
    return 0;
}

int update_scroll() {
    int i;
    int atMax;

    i = 0;
    while (i < SCROLL_SPEED) {
        if (scrollDir == 0) {
            atMax = 0;
            if (scrollXHigh > MAX_SCROLL_X_HIGH) { atMax = 1; }
            if (scrollXHigh == MAX_SCROLL_X_HIGH) {
                if (scrollXLow >= MAX_SCROLL_X_LOW) { atMax = 1; }
            }
            if (atMax == 1) {
                scrollDir = 1;
            } else {
                scrollXLow = scrollXLow + 1;
                if (scrollXLow == 0) { scrollXHigh = scrollXHigh + 1; }
            }
        } else {
            if (scrollXHigh == 0) {
                if (scrollXLow == 0) { scrollDir = 0; }
            }
            if (scrollDir == 1) {
                scrollXLow = scrollXLow - 1;
                if (scrollXLow == 255) { scrollXHigh = scrollXHigh - 1; }
            }
        }
        i = i + 1;
    }

    apply_scroll();
    return 0;
}

// ---- куб (8 вершин ±30, 12 треугольников - те же данные, что в
// C/DEMOS/CUBE3D.ASM, только собраны через emit()/tri() вместо
// развёрнутого ассемблера) ----

int v0() { poke(GPU3D_VX_LOW, 226); poke(GPU3D_VX_HIGH, 255); poke(GPU3D_VY_LOW, 226); poke(GPU3D_VY_HIGH, 255); poke(GPU3D_VZ_LOW, 226); poke(GPU3D_VZ_HIGH, 255); return 0; }
int v1() { poke(GPU3D_VX_LOW, 30);  poke(GPU3D_VX_HIGH, 0);   poke(GPU3D_VY_LOW, 226); poke(GPU3D_VY_HIGH, 255); poke(GPU3D_VZ_LOW, 226); poke(GPU3D_VZ_HIGH, 255); return 0; }
int v2() { poke(GPU3D_VX_LOW, 30);  poke(GPU3D_VX_HIGH, 0);   poke(GPU3D_VY_LOW, 30);  poke(GPU3D_VY_HIGH, 0);   poke(GPU3D_VZ_LOW, 226); poke(GPU3D_VZ_HIGH, 255); return 0; }
int v3() { poke(GPU3D_VX_LOW, 226); poke(GPU3D_VX_HIGH, 255); poke(GPU3D_VY_LOW, 30);  poke(GPU3D_VY_HIGH, 0);   poke(GPU3D_VZ_LOW, 226); poke(GPU3D_VZ_HIGH, 255); return 0; }
int v4() { poke(GPU3D_VX_LOW, 226); poke(GPU3D_VX_HIGH, 255); poke(GPU3D_VY_LOW, 226); poke(GPU3D_VY_HIGH, 255); poke(GPU3D_VZ_LOW, 30);  poke(GPU3D_VZ_HIGH, 0);   return 0; }
int v5() { poke(GPU3D_VX_LOW, 30);  poke(GPU3D_VX_HIGH, 0);   poke(GPU3D_VY_LOW, 226); poke(GPU3D_VY_HIGH, 255); poke(GPU3D_VZ_LOW, 30);  poke(GPU3D_VZ_HIGH, 0);   return 0; }
int v6() { poke(GPU3D_VX_LOW, 30);  poke(GPU3D_VX_HIGH, 0);   poke(GPU3D_VY_LOW, 30);  poke(GPU3D_VY_HIGH, 0);   poke(GPU3D_VZ_LOW, 30);  poke(GPU3D_VZ_HIGH, 0);   return 0; }
int v7() { poke(GPU3D_VX_LOW, 226); poke(GPU3D_VX_HIGH, 255); poke(GPU3D_VY_LOW, 30);  poke(GPU3D_VY_HIGH, 0);   poke(GPU3D_VZ_LOW, 30);  poke(GPU3D_VZ_HIGH, 0);   return 0; }

int emit(int vertexId, int r, int g, int b) {
    if (vertexId == 0) { v0(); }
    if (vertexId == 1) { v1(); }
    if (vertexId == 2) { v2(); }
    if (vertexId == 3) { v3(); }
    if (vertexId == 4) { v4(); }
    if (vertexId == 5) { v5(); }
    if (vertexId == 6) { v6(); }
    if (vertexId == 7) { v7(); }
    poke(GPU3D_VR, r);
    poke(GPU3D_VG, g);
    poke(GPU3D_VB, b);
    poke(GPU3D_COMMAND, 1);   // SUBMIT_VERTEX
    return 0;
}

int tri(int a, int b, int c, int r, int g, int bl) {
    emit(a, r, g, bl);
    emit(b, r, g, bl);
    emit(c, r, g, bl);
    poke(GPU3D_COMMAND, 2);   // DRAW_TRIANGLE
    return 0;
}

int draw_cube() {
    poke(GPU3D_COMMAND, 3);   // CLEAR

    tri(0, 1, 2, 255, 0, 0);     // -Z, красная
    tri(0, 2, 3, 255, 0, 0);
    tri(4, 5, 6, 0, 255, 0);     // +Z, зелёная
    tri(4, 6, 7, 0, 255, 0);
    tri(0, 1, 5, 0, 0, 255);     // -Y, синяя
    tri(0, 5, 4, 0, 0, 255);
    tri(3, 2, 6, 255, 255, 0);   // +Y, жёлтая
    tri(3, 6, 7, 255, 255, 0);
    tri(0, 4, 7, 255, 0, 255);   // -X, малиновая
    tri(0, 7, 3, 255, 0, 255);
    tri(1, 2, 6, 0, 255, 255);   // +X, голубая
    tri(1, 6, 5, 0, 255, 255);

    poke(GPU3D_COMMAND, 4);   // PRESENT
    return 0;
}

int rotate_cube() {
    // +2 к YAW за кадр, как в CUBE3D.ASM - двумя шагами +1 (перенос в
    // high byte детектим по обёртыванию через 0, тот же приём, что и у
    // scrollXLow/scrollXHigh выше).
    yawLow = yawLow + 1;
    if (yawLow == 0) { yawHigh = yawHigh + 1; }
    yawLow = yawLow + 1;
    if (yawLow == 0) { yawHigh = yawHigh + 1; }

    poke(GPU3D_OBJ_YAW_LOW, yawLow);
    poke(GPU3D_OBJ_YAW_HIGH, yawHigh);
    return 0;
}

// ---- снежинки: позиция - взаимно простой обход сетки (см. заголовок
// файла, COL_STEP/ROW_STEP), цвет - линейный конгруэнтный генератор ----

int rng_next() {
    rng = rng * 5 + 1;
    return rng;
}

// Следующая ячейка обхода - вызывается ДО print_char/set_color в
// place_snowflake(), поэтому первая снежинка всегда падает в (0,0), а
// не пропускает её.
int advance_snow_position() {
    snowColStep = snowColStep + 1;
    if (snowColStep >= 80) {
        snowColStep = 0;
        snowRow = snowRow + ROW_STEP;
        if (snowRow >= 25) { snowRow = snowRow - 25; }
    }

    snowCol = snowCol + COL_STEP;
    if (snowCol >= 80) { snowCol = snowCol - 80; }
    return 0;
}

int place_snowflake() {
    int col;
    int row;
    int colorPick;
    int fg;

    col = snowCol;
    row = snowRow;
    advance_snow_position();

    rng_next();
    colorPick = rng % 6;

    fg = 15;   // белый - запасной вариант, colorPick всегда 0-5 ниже
    if (colorPick == 0) { fg = 9; }    // светло-синий
    if (colorPick == 1) { fg = 11; }   // светло-голубой
    if (colorPick == 2) { fg = 13; }   // светло-малиновый
    if (colorPick == 3) { fg = 14; }   // жёлтый
    if (colorPick == 4) { fg = 10; }   // светло-зелёный
    if (colorPick == 5) { fg = 12; }   // светло-красный

    print_char(col, row, 42);   // '*'
    set_color(col, row, fg, BG_TRANSPARENT);
    return 0;
}

int main() {
    int status;
    int key;

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
    place_corner_sprite();

    poke(VIDEOCARD_COMMAND, 1);   // MODE_ON - автоматически прячет консоль

    poke(GPU3D_CAM_Z_LOW, 106);
    poke(GPU3D_CAM_Z_HIGH, 255);   // камера на -150 по Z, см. CUBE3D.ASM

    // Комбинированный режим - явно возвращаем консоль поверх графики
    // (см. ConsoleLayer.h) и чистим её, чтобы снежинки сыпались на
    // пустой экран, а не поверх старого текста шелла.
    poke(CONSOLE_VISIBLE, 1);
    clear_screen();

    scrollXLow = 0;
    scrollXHigh = 0;
    scrollDir = 0;
    yawLow = 0;
    yawHigh = 0;
    rng = peek(CLOCK_LOW) + 1;   // сид цвета от текущих мс - разный при каждом запуске
    frameCount = 0;
    snowCol = 0;
    snowRow = 0;
    snowColStep = 0;
    running = 1;

    while (running == 1) {
        key = peek(KEYBOARD_DATA);
        if (key == KEY_CTRL_Q) { running = 0; }

        update_scroll();
        rotate_cube();
        draw_cube();

        frameCount = frameCount + 1;
        if (frameCount >= 3) {
            frameCount = 0;
            place_snowflake();
        }

        wait_ms(17);   // ~60 кадров/сек
    }

    poke(VIDEOCARD_COMMAND, 2);   // MODE_OFF - вернёт консоль автоматически
    clear_screen();

    return 0;
}
