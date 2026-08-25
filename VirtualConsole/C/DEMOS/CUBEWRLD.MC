// CUBEWRLD.MC - демка "пол из кубов": уровень (высота стопки кубов на
// клетке - 0/1/2) грузится из LEVEL.TXT через MatrixLoader, пол рисуется
// кубами через GEOM3D.MC (единый девайс Gpu3D - 3D-ускоритель + свет +
// математический сопроцессор 16/32 бит, см. misty-zooming-bee.md про то,
// почему это теперь одно устройство, а не три), камера крутится мышью
// (см. Mouse.h), персонаж (=камера, вид от первого лица) двигается
// стрелками ОТНОСИТЕЛЬНО направления взгляда - вся тригонометрия (sin/cos
// yaw) считается не тут, а на математическом сопроцессоре Gpu3D (см.
// GEOM3D.MC::move_camera), т.к. мини-C умеет только 8-битную арифметику
// без тригонометрии (см. ASSEMBLY.md, "The long type").
//
// Пол рисуется аппаратной командой DRAW_CUBE (GEOM3D.MC::draw_cube_at) -
// один куб это ~13 poke() вместо 468 (36 вершин по 13 байт вручную) - это
// было главной причиной тормозов первой версии этой демки, см.
// misty-zooming-bee.md. Кубы текстурированы 32x32-тайлами из TILES.PNG
// (тот же атлас, что у TSCROLL.MC/SNOW3D.MC) - загрузка текстур встроена
// прямо в Gpu3D, своя "быстрая память" на 8 слотов (не отдельное
// устройство, см. misty-zooming-bee.md).
//
// Демка ограничена уровнями до 64 клеток (8x8, как LEVEL.TXT) - позиции
// кубов кэшируются один раз при загрузке в фиксированные массивы
// (мини-C не умеет в массивы переменного размера), пересчитывать 16-битные
// мировые координаты каждой клетки КАЖДЫЙ КАДР было бы зря потраченным
// временем ради статичного уровня.
//
// Ctrl+Q - выход. Собирается командой "build cubewrld.mc", запускается
// как "cubewrld".

#include "GEOM3D.MC"

const KEY_CTRL_Q = 17;
const KEY_UP = 72;
const KEY_DOWN = 80;
const KEY_LEFT = 75;
const KEY_RIGHT = 77;

const MAX_CELLS = 64;
const CUBE_SIZE = 40;
const CUBE_HALF = 20;      // используется для РАССТАНОВКИ клеток (шаг сетки)
const CUBE_DRAW_HALF = 19; // используется для ОТРИСОВКИ - чуть меньше CUBE_HALF,
                            // чтобы между соседними кубами был зазор в 2 юнита:
                            // при ровно стыкующихся гранях (0 зазора) грани
                            // соседних кубов лежат в одной плоскости и мерцают
                            // от z-fighting (выглядит как кубы "проникают" друг
                            // в друга на стыке) - см. misty-zooming-bee.md
const MOVE_SPEED = 4;

// Текстурные слоты Gpu3D (1-8, см. GEOM3D.MC) - пол первого слоя и
// стопки второго слоя красятся разными тайлами из TILES.PNG, чтобы
// визуально отличались.
const TEX_SLOT_FLOOR = 1;
const TEX_SLOT_LAYER2 = 2;

int cellCenterXLow[MAX_CELLS];
int cellCenterXHigh[MAX_CELLS];
int cellCenterZLow[MAX_CELLS];
int cellCenterZHigh[MAX_CELLS];
int cellHeight[MAX_CELLS];
int cellCount;

int originXLow; int originXHigh;
int originZLow; int originZHigh;
int layer2YLow; int layer2YHigh;

int wait_ms(int ms) {
    poke(CLOCK_LOW, 0);
    while (peek(CLOCK_LOW) < ms) {
    }
    return 0;
}

// forward/strafe - уже правильно знаковые пары low/high (для "назад"/
// "влево" вызывающий код сам получает их через neg16 ДО вызова - см.
// main()), сама move_camera никогда не создаёт отрицательное число с
// нуля, только комбинирует уже готовые пары через математику Gpu3D.
int move_camera(int forwardLow, int forwardHigh, int strafeLow, int strafeHigh) {
    int yawLow; int yawHigh;
    int sinLow; int sinHigh;
    int cosLow; int cosHigh;
    int termLow; int termHigh;
    int dxLow; int dxHigh;
    int dzLow; int dzHigh;

    yawLow = peek(GPU3D_CAM_YAW_LOW);
    yawHigh = peek(GPU3D_CAM_YAW_HIGH);

    sin16(yawLow, yawHigh);
    sinLow = mathResultLow; sinHigh = mathResultHigh;

    cos16(yawLow, yawHigh);
    cosLow = mathResultLow; cosHigh = mathResultHigh;

    // dx = (forward*sin(yaw) + strafe*cos(yaw)) / 100 - fixed-point *100
    // от sin16/cos16 (см. GEOM3D.MC), делим обратно в мировые единицы.
    mul16(forwardLow, forwardHigh, sinLow, sinHigh);
    termLow = mathResultLow; termHigh = mathResultHigh;
    mul16(strafeLow, strafeHigh, cosLow, cosHigh);
    add16(termLow, termHigh, mathResultLow, mathResultHigh);
    div16(mathResultLow, mathResultHigh, 100, 0);
    dxLow = mathResultLow; dxHigh = mathResultHigh;

    // dz = (forward*cos(yaw) - strafe*sin(yaw)) / 100
    mul16(forwardLow, forwardHigh, cosLow, cosHigh);
    termLow = mathResultLow; termHigh = mathResultHigh;
    mul16(strafeLow, strafeHigh, sinLow, sinHigh);
    sub16(termLow, termHigh, mathResultLow, mathResultHigh);
    div16(mathResultLow, mathResultHigh, 100, 0);
    dzLow = mathResultLow; dzHigh = mathResultHigh;

    add16(peek(GPU3D_CAM_X_LOW), peek(GPU3D_CAM_X_HIGH), dxLow, dxHigh);
    poke(GPU3D_CAM_X_LOW, mathResultLow);
    poke(GPU3D_CAM_X_HIGH, mathResultHigh);

    add16(peek(GPU3D_CAM_Z_LOW), peek(GPU3D_CAM_Z_HIGH), dzLow, dzHigh);
    poke(GPU3D_CAM_Z_LOW, mathResultLow);
    poke(GPU3D_CAM_Z_HIGH, mathResultHigh);

    return 0;
}

int update_mouse_look() {
    int sign;
    int mag;
    int yawLow; int yawHigh;
    int pitchLow; int pitchHigh;

    // ВАЖНО: знак читается ДО модуля - чтение *_MAG обнуляет накопитель
    // (см. Mouse::read), после чего *_SIGN уже не отражает старое
    // значение.
    sign = peek(MOUSE_DELTA_X_SIGN);
    mag = peek(MOUSE_DELTA_X_MAG);
    if (mag > 0) {
        yawLow = peek(GPU3D_CAM_YAW_LOW);
        yawHigh = peek(GPU3D_CAM_YAW_HIGH);

        if (sign == 0) { add16(yawLow, yawHigh, mag, 0); }
        if (sign == 1) { sub16(yawLow, yawHigh, mag, 0); }

        poke(GPU3D_CAM_YAW_LOW, mathResultLow);
        poke(GPU3D_CAM_YAW_HIGH, mathResultHigh);
    }

    sign = peek(MOUSE_DELTA_Y_SIGN);
    mag = peek(MOUSE_DELTA_Y_MAG);
    if (mag > 0) {
        pitchLow = peek(GPU3D_CAM_PITCH_LOW);
        pitchHigh = peek(GPU3D_CAM_PITCH_HIGH);

        // Знак пока подобран "на глаз" (мышь вверх = смотреть вверх) -
        // если на живом запуске окажется наоборот, поменять местами
        // add16/sub16 здесь.
        if (sign == 0) { sub16(pitchLow, pitchHigh, mag, 0); }
        if (sign == 1) { add16(pitchLow, pitchHigh, mag, 0); }

        poke(GPU3D_CAM_PITCH_LOW, mathResultLow);
        poke(GPU3D_CAM_PITCH_HIGH, mathResultHigh);
    }

    return 0;
}

int load_level() {
    str_copy(matrixLoaderName, "LEVEL.TXT");
    poke(MATRIXLOADER_COMMAND, 1);
    return peek(MATRIXLOADER_STATUS);
}

// str_copy() принимает только строковый литерал (см. GEOM3D.MC про
// gpu3dTexName) - поэтому имя файла атласа зашито тут, а не параметром.
int load_floor_textures() {
    int status;

    str_copy(gpu3dTexName, "TILES.PNG");
    poke(GPU3D_TEX_COMMAND, GPU3D_TEX_CMD_LOAD);
    status = peek(GPU3D_TEX_STATUS);
    if (status != 0) { return status; }

    // Координаты - те же гарантированно валидные 32x32-регионы TILES.PNG,
    // что уже использует C/DEMOS/SNOW3D.MC::extract_all_tiles() (первые
    // два из восьми) - не гадаем новые вслепую.
    status = load_texture_tile(TEX_SLOT_FLOOR, 0, 0, 0, 0);
    if (status != 0) { return status; }

    status = load_texture_tile(TEX_SLOT_LAYER2, 32, 0, 64, 0);
    return status;
}

// Считает мировые координаты каждой клетки ОДИН РАЗ (уровень статичен) и
// кладёт их в cellCenterX*/cellCenterZ*/cellHeight - см. заголовок файла.
int build_level_cache() {
    int gridWidth;
    int gridHeight;
    int row;
    int col;

    gridWidth = peek(MATRIXLOADER_WIDTH_LOW);
    gridHeight = peek(MATRIXLOADER_HEIGHT_LOW);

    // originX/Z - мировые координаты левого-переднего угла сетки, чтобы
    // сетка была отцентрована вокруг (0,0) - see MOVE_SPEED комментарий
    // выше про neg16 вместо ручных отрицательных литералов.
    mul16(gridWidth, 0, CUBE_SIZE, 0);
    div16(mathResultLow, mathResultHigh, 2, 0);
    neg16(mathResultLow, mathResultHigh);
    originXLow = mathResultLow; originXHigh = mathResultHigh;

    mul16(gridHeight, 0, CUBE_SIZE, 0);
    div16(mathResultLow, mathResultHigh, 2, 0);
    neg16(mathResultLow, mathResultHigh);
    originZLow = mathResultLow; originZHigh = mathResultHigh;

    neg16(CUBE_SIZE, 0);
    layer2YLow = mathResultLow; layer2YHigh = mathResultHigh;

    cellCount = 0;
    row = 0;
    while (row < gridHeight) {
        col = 0;
        while (col < gridWidth) {
            poke(MATRIXLOADER_CELL_X_LOW, col);
            poke(MATRIXLOADER_CELL_X_HIGH, 0);
            poke(MATRIXLOADER_CELL_Y_LOW, row);
            poke(MATRIXLOADER_CELL_Y_HIGH, 0);

            mul16(col, 0, CUBE_SIZE, 0);
            add16(originXLow, originXHigh, mathResultLow, mathResultHigh);
            add16(mathResultLow, mathResultHigh, CUBE_HALF, 0);
            cellCenterXLow[cellCount] = mathResultLow;
            cellCenterXHigh[cellCount] = mathResultHigh;

            mul16(row, 0, CUBE_SIZE, 0);
            add16(originZLow, originZHigh, mathResultLow, mathResultHigh);
            add16(mathResultLow, mathResultHigh, CUBE_HALF, 0);
            cellCenterZLow[cellCount] = mathResultLow;
            cellCenterZHigh[cellCount] = mathResultHigh;

            cellHeight[cellCount] = peek(MATRIXLOADER_CELL_VALUE);

            cellCount = cellCount + 1;
            col = col + 1;
        }
        row = row + 1;
    }

    return 0;
}

int draw_floor() {
    int i;

    poke(GPU3D_COMMAND, GPU3D_CMD_CLEAR);

    i = 0;
    while (i < cellCount) {
        if (cellHeight[i] > 0) {
            draw_cube_at(cellCenterXLow[i], cellCenterXHigh[i], 0, 0,
                cellCenterZLow[i], cellCenterZHigh[i], CUBE_DRAW_HALF, 0, 180, 180, 190, TEX_SLOT_FLOOR);
        }
        if (cellHeight[i] > 1) {
            draw_cube_at(cellCenterXLow[i], cellCenterXHigh[i], layer2YLow, layer2YHigh,
                cellCenterZLow[i], cellCenterZHigh[i], CUBE_DRAW_HALF, 0, 150, 150, 210, TEX_SLOT_LAYER2);
        }
        i = i + 1;
    }

    poke(GPU3D_COMMAND, GPU3D_CMD_PRESENT);
    return 0;
}

int main() {
    int status;
    int key;
    int running;

    status = load_level();
    if (status != 0) {
        clear_screen();
        print_str(0, 0, "level load error");
        return 1;
    }
    build_level_cache();

    status = load_floor_textures();
    if (status != 0) {
        clear_screen();
        print_str(0, 0, "texture load error");
        return 1;
    }

    // Один направленный источник + фоновая засветка - см. Gpu3D.h.
    // Направление подобрать живым тестом, если грани будут выглядеть
    // "плоско" или свет ляжет на неожиданную сторону.
    poke(GPU3D_LIGHT_DIR_X, NORMAL_NEG_UNIT);
    poke(GPU3D_LIGHT_DIR_Y, NORMAL_NEG_UNIT);
    poke(GPU3D_LIGHT_DIR_Z, NORMAL_ZERO);
    poke(GPU3D_LIGHT_R, 255);
    poke(GPU3D_LIGHT_G, 255);
    poke(GPU3D_LIGHT_B, 255);
    poke(GPU3D_AMBIENT, 70);

    // Камера над полом, чуть в стороне от центра, смотрит на сетку -
    // высота/положение подобрать живым тестом.
    poke(GPU3D_CAM_X_LOW, 0); poke(GPU3D_CAM_X_HIGH, 0);
    poke(GPU3D_CAM_Y_LOW, 226); poke(GPU3D_CAM_Y_HIGH, 255); // -30
    poke(GPU3D_CAM_Z_LOW, 106); poke(GPU3D_CAM_Z_HIGH, 255); // -150
    poke(GPU3D_CAM_YAW_LOW, 0); poke(GPU3D_CAM_YAW_HIGH, 0);
    poke(GPU3D_CAM_PITCH_LOW, 0); poke(GPU3D_CAM_PITCH_HIGH, 0);

    poke(VIDEOCARD_COMMAND, 1); // MODE_ON - см. SNOW3D.MC, прячет консоль автоматически
    poke(MOUSE_CONTROL, 1);

    clear_screen();

    running = 1;
    while (running == 1) {
        key = peek(KEYBOARD_DATA);
        if (key == KEY_CTRL_Q) { running = 0; }

        if (key == KEY_UP) { move_camera(MOVE_SPEED, 0, 0, 0); }
        if (key == KEY_DOWN) { neg16(MOVE_SPEED, 0); move_camera(mathResultLow, mathResultHigh, 0, 0); }
        if (key == KEY_RIGHT) { move_camera(0, 0, MOVE_SPEED, 0); }
        if (key == KEY_LEFT) { neg16(MOVE_SPEED, 0); move_camera(0, 0, mathResultLow, mathResultHigh); }

        update_mouse_look();
        draw_floor();

        wait_ms(17); // ~60 кадров/сек
    }

    poke(MOUSE_CONTROL, 0);
    poke(VIDEOCARD_COMMAND, 2); // MODE_OFF
    clear_screen();

    return 0;
}
