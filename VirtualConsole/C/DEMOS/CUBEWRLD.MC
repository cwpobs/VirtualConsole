// CUBEWRLD.MC - демка "уровень из кубов": сетка 14x14 грузится из
// LEVEL.TXT через MatrixLoader - значение клетки теперь высота СТЕНЫ
// над полом (0/1/2 блока), пол при этом есть ВСЕГДА, на каждой клетке
// (см. draw_floor()). Кубы рисуются через GEOM3D.MC (единый девайс
// Gpu3D - 3D-ускоритель + свет + математический сопроцессор 16/32 бит,
// см. misty-zooming-bee.md про то, почему это теперь одно устройство, а
// не три), камера крутится мышью (см. Mouse.h), персонаж (=камера, вид
// от первого лица) двигается стрелками ОТНОСИТЕЛЬНО направления взгляда
// - вся тригонометрия (sin/cos yaw) считается не тут, а на
// математическом сопроцессоре Gpu3D (см. GEOM3D.MC::compute_move_delta),
// т.к. мини-C умеет только 8-битную арифметику без тригонометрии (см.
// ASSEMBLY.md, "The long type").
//
// Пол рисуется аппаратной командой DRAW_CUBE (GEOM3D.MC::draw_cube_at) -
// один куб это ~13 poke() вместо 468 (36 вершин по 13 байт вручную) - это
// было главной причиной тормозов первой версии этой демки, см.
// misty-zooming-bee.md. Кубы текстурированы 32x32-тайлами из TILES.PNG
// (тот же атлас, что у TSCROLL.MC/SNOW3D.MC) - загрузка текстур встроена
// прямо в Gpu3D, своя "быстрая память" на 8 слотов (не отдельное
// устройство, см. misty-zooming-bee.md).
//
// Демка ограничена уровнями до MAX_CELLS клеток (196 = 14x14, как
// LEVEL.TXT - см. константу ниже) - позиции кубов кэшируются один раз
// при загрузке в фиксированные массивы (мини-C не умеет в массивы
// переменного размера), пересчитывать 16-битные мировые координаты
// каждой клетки КАЖДЫЙ КАДР было бы зря потраченным временем ради
// статичного уровня.
//
// Физика (столкновения с кубами + бесконечный пол + гравитация) - через
// отдельный физический ускоритель Phys3D (см. C/DEV/LIB/PHYS3D.MC и
// misty-zooming-bee.md) - сознательно не связан с Gpu3D. Кубы уровня
// определяются устройству ОДИН РАЗ при загрузке (как текстуры), за кадр
// идёт только phys_step() - "подвинь игрока, разреши коллизии".
//
// Стрелки читаются через KeyState (см. KeyState.h) - "зажата ли клавиша
// ПРЯМО СЕЙЧАС", а не через очередь Keyboard/KEYBOARD_DATA (та рывками
// движение не тянет - см. misty-zooming-bee.md). Ctrl+Q по-прежнему
// читается через старую очередь - разовое действие, ей самое место.
//
// Pitch (взгляд вверх/вниз) зажат в ±89° - без этого камеру можно
// провернуть "через горизонт" (гимбал-эффект угла Эйлера).
//
// Ctrl+Q - выход. Собирается командой "build cubewrld.mc", запускается
// как "cubewrld".

#include "GEOM3D.MC"
#include "PHYS3D.MC"

const KEY_CTRL_Q = 17;

const MAX_CELLS = 196; // 14x14, см. LEVEL.TXT - строго < 256 (см. ASSEMBLY.md про предел индекса обычного int-массива)
const CUBE_SIZE = 40;
const CUBE_HALF = 20;      // используется и для РАССТАНОВКИ клеток (шаг сетки), и для ОТРИСОВКИ
const CUBE_DRAW_HALF = CUBE_HALF; // раньше был чуть меньше CUBE_HALF (зазор
                            // в 2 юнита против z-fighting на стыке граней) -
                            // по просьбе пользователя грани теперь стыкуются
                            // ровно, без зазора, ради сплошных стен/пола (см.
                            // misty-zooming-bee.md) - если на живом запуске
                            // будет заметно мерцание на стыках, вернуть
                            // например CUBE_HALF - 2
const MOVE_SPEED = 4;

// Текстурные слоты Gpu3D (1-8, см. GEOM3D.MC) - пол и стены красятся
// разными тайлами из TILES.PNG, чтобы визуально отличались.
const TEX_SLOT_FLOOR = 1;
const TEX_SLOT_WALL = 2;

// Ограничение pitch (взгляд вверх/вниз), градусы - без него камеру можно
// провернуть "через горизонт" из-за угла Эйлера (см. update_mouse_look()).
const PITCH_LIMIT = 89;

// Физика (см. C/DEV/LIB/PHYS3D.MC). Числа подобраны разумно, но почти
// наверняка потребуют подстройки на живом запуске (см.
// misty-zooming-bee.md) - конвенция знака здесь та же, что в Phys3D.cpp:
// "вверх" = РОСТ Y (подтверждено живым тестом - второй блок стены на
// +CUBE_SIZE стоит НАД первым), значит падение - это УМЕНЬШЕНИЕ Y, а
// "на полу" - это ВЫШЕ GROUND_Y на радиус, не ниже. Игрок - сфера (см.
// Phys3D.h), один радиус.
const GRAVITY_UNITS = 2;
const GROUND_Y = CUBE_HALF;   // верхняя (ходовая) грань пола - пол центрирован в 0, половина CUBE_HALF
// Радиус игрока = радиус камеры (camera == player center, без отдельного
// смещения "глаз") - был 12, из-за чего камера сидела всего на 12 юнитов
// выше пола (GROUND_Y+radius) и при взгляде вниз проваливалась взглядом
// в геометрию соседних кубов пола. Увеличен - даёт запас и от пола
// снизу, и от стен сбоку (сфера того же радиуса используется в
// столкновениях, см. Phys3D.cpp) - см. misty-zooming-bee.md.
const PLAYER_RADIUS = 18;
const PLAYER_SPAWN_Y = GROUND_Y + PLAYER_RADIUS;   // ровно "на полу", центр сферы НАД грунтом - см. main()

// Клетка спавна - заведомо открытая (0) клетка ВНУТРИ периметра стен,
// см. LEVEL.TXT (14 в ширину, спавн в (row=6, col=6), индекс в
// cellCenterX*/Z* - row*gridWidth+col = 6*14+6). Персонаж стартует
// ВНУТРИ уровня, а не снаружи - см. misty-zooming-bee.md (в прошлой
// итерации было наоборот, теперь заменено по просьбе пользователя).
const SPAWN_CELL_INDEX = 90;

// Прицел - '+' по центру текстовой сетки 80x25 (см. main()).
const CROSSHAIR_COL = 40;
const CROSSHAIR_ROW = 12;
const CROSSHAIR_CHAR = 43;   // '+'
const CROSSHAIR_FG = 15;
const BG_TRANSPARENT = 8;    // см. TextAttr::TRANSPARENT_BG

int cellCenterXLow[MAX_CELLS];
int cellCenterXHigh[MAX_CELLS];
int cellCenterZLow[MAX_CELLS];
int cellCenterZHigh[MAX_CELLS];
int cellHeight[MAX_CELLS];
int cellCount;

int originXLow; int originXHigh;
int originZLow; int originZHigh;
int layer2YLow; int layer2YHigh;   // высота ПЕРВОГО блока стены (над полом)
int wall2YLow; int wall2YHigh;     // высота ВТОРОГО блока стены (над первым)
int boxSlotCount;                  // отдельный счётчик слотов Phys3D - только для стен, не для каждой клетки сетки

int moveDeltaXLow; int moveDeltaXHigh;
int moveDeltaZLow; int moveDeltaZHigh;

int wait_ms(int ms) {
    poke(CLOCK_LOW, 0);
    while (peek(CLOCK_LOW) < ms) {
    }
    return 0;
}

// forward/strafe - уже правильно знаковые пары low/high (нули, если
// соответствующая пара стрелок не зажата - см. main()). Считает желаемое
// мировое смещение (dx,dz) ОТНОСИТЕЛЬНО направления взгляда и кладёт в
// moveDeltaX*/moveDeltaZ* - раньше это сразу писалось в GPU3D_CAM_X/Z,
// теперь вместо этого идёт в Phys3D (phys_step()) на разрешение
// коллизий, а в камеру попадает уже РАЗРЕШЁННАЯ позиция игрока (см.
// main()).
int compute_move_delta(int forwardLow, int forwardHigh, int strafeLow, int strafeHigh) {
    int yawLow; int yawHigh;
    int sinLow; int sinHigh;
    int cosLow; int cosHigh;
    int termLow; int termHigh;

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
    moveDeltaXLow = mathResultLow; moveDeltaXHigh = mathResultHigh;

    // dz = (forward*cos(yaw) - strafe*sin(yaw)) / 100
    mul16(forwardLow, forwardHigh, cosLow, cosHigh);
    termLow = mathResultLow; termHigh = mathResultHigh;
    mul16(strafeLow, strafeHigh, sinLow, sinHigh);
    sub16(termLow, termHigh, mathResultLow, mathResultHigh);
    div16(mathResultLow, mathResultHigh, 100, 0);
    moveDeltaZLow = mathResultLow; moveDeltaZHigh = mathResultHigh;

    return 0;
}

int update_mouse_look() {
    int sign;
    int mag;
    int yawLow; int yawHigh;
    int pitchLow; int pitchHigh;
    int negLimitLow; int negLimitHigh;

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

        // Знак подтверждён живым тестом (было наоборот - см.
        // misty-zooming-bee.md).
        if (sign == 0) { add16(pitchLow, pitchHigh, mag, 0); }
        if (sign == 1) { sub16(pitchLow, pitchHigh, mag, 0); }

        pitchLow = mathResultLow; pitchHigh = mathResultHigh;

        // Зажать в [-PITCH_LIMIT, +PITCH_LIMIT] - без этого угол Эйлера
        // даёт "перепрыгнуть через горизонт" (камера переворачивается),
        // если крутить мышью вверх/вниз без остановки. Оба сравнения -
        // через уже готовый sub16 (см. GEOM3D.MC): результат sub16 -
        // настоящее знаковое 16-битное число в mathResultLow/High, а
        // "результат >= 0" эквивалентно "старший байт < 128" (бит знака
        // сброшен) - без единого нового регистра/устройства.
        sub16(pitchLow, pitchHigh, PITCH_LIMIT, 0);
        if (mathResultHigh < 128) {   // pitch - LIMIT >= 0, т.е. pitch >= LIMIT
            pitchLow = PITCH_LIMIT; pitchHigh = 0;
        }

        neg16(PITCH_LIMIT, 0);
        negLimitLow = mathResultLow; negLimitHigh = mathResultHigh;
        sub16(pitchLow, pitchHigh, negLimitLow, negLimitHigh);
        if (mathResultHigh >= 128) {   // pitch - (-LIMIT) < 0, т.е. pitch < -LIMIT
            pitchLow = negLimitLow; pitchHigh = negLimitHigh;
        }

        poke(GPU3D_CAM_PITCH_LOW, pitchLow);
        poke(GPU3D_CAM_PITCH_HIGH, pitchHigh);
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

    status = load_texture_tile(TEX_SLOT_WALL, 32, 0, 64, 0);
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

    // +CUBE_SIZE, не -CUBE_SIZE - на экране "вверх" оказался знак +Y, не
    // -Y (было наоборот, см. misty-zooming-bee.md) - блок стены должен
    // стоять НАД полом, а не под ним. Обычные константы, MathUnit не
    // нужен (2*CUBE_SIZE=80 умещается в один байт).
    layer2YLow = CUBE_SIZE; layer2YHigh = 0;
    wall2YLow = CUBE_SIZE * 2; wall2YHigh = 0;

    cellCount = 0;
    boxSlotCount = 0;
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

            // Значение клетки теперь - высота СТЕНЫ над полом (0 = нет
            // стены, только пол; 1/2 - один/два блока стены) - пол есть
            // ВСЕГДА, на каждой клетке (см. draw_floor()), физического
            // бокса под ним не нужно - его роль уже играет бесконечная
            // плоскость GROUND_Y (см. Phys3D). Боксы - только под
            // стенами, по одному на каждый блок, слот - через ОТДЕЛЬНЫЙ
            // счётчик boxSlotCount (не cellCount*2 - число реально
            // используемых боксов теперь зависит от количества стен, а
            // не от размера сетки, см. misty-zooming-bee.md).
            cellHeight[cellCount] = peek(MATRIXLOADER_CELL_VALUE);

            if (cellHeight[cellCount] > 0) {
                phys_define_box(boxSlotCount,
                    cellCenterXLow[cellCount], cellCenterXHigh[cellCount],
                    layer2YLow, layer2YHigh,
                    cellCenterZLow[cellCount], cellCenterZHigh[cellCount],
                    CUBE_HALF, CUBE_HALF, CUBE_HALF);
                boxSlotCount = boxSlotCount + 1;
            }
            if (cellHeight[cellCount] > 1) {
                phys_define_box(boxSlotCount,
                    cellCenterXLow[cellCount], cellCenterXHigh[cellCount],
                    wall2YLow, wall2YHigh,
                    cellCenterZLow[cellCount], cellCenterZHigh[cellCount],
                    CUBE_HALF, CUBE_HALF, CUBE_HALF);
                boxSlotCount = boxSlotCount + 1;
            }

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
        // Пол - ВСЕГДА, на каждой клетке (см. build_level_cache) - иначе
        // на проходимых клетках без стены не видно, что там вообще есть
        // пол, хотя физически игрок там уже стоит на GROUND_Y (см.
        // misty-zooming-bee.md).
        draw_cube_at(cellCenterXLow[i], cellCenterXHigh[i], 0, 0,
            cellCenterZLow[i], cellCenterZHigh[i], CUBE_DRAW_HALF, 0, 180, 180, 190, TEX_SLOT_FLOOR);

        if (cellHeight[i] > 0) {
            draw_cube_at(cellCenterXLow[i], cellCenterXHigh[i], layer2YLow, layer2YHigh,
                cellCenterZLow[i], cellCenterZHigh[i], CUBE_DRAW_HALF, 0, 150, 150, 210, TEX_SLOT_WALL);
        }
        if (cellHeight[i] > 1) {
            draw_cube_at(cellCenterXLow[i], cellCenterXHigh[i], wall2YLow, wall2YHigh,
                cellCenterZLow[i], cellCenterZHigh[i], CUBE_DRAW_HALF, 0, 150, 150, 210, TEX_SLOT_WALL);
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

    // Физика - гравитация/радиус игрока/"горизонт" (см. C/DEV/LIB/PHYS3D.MC
    // и константы выше - GRAVITY_UNITS/GROUND_Y/PLAYER_RADIUS).
    poke(PHYS_GRAVITY_LOW, GRAVITY_UNITS); poke(PHYS_GRAVITY_HIGH, 0);
    poke(PHYS_GROUND_Y_LOW, GROUND_Y); poke(PHYS_GROUND_Y_HIGH, 0);
    poke(PHYS_PLAYER_RADIUS, PLAYER_RADIUS);

    // Старт - ВНУТРИ периметра стен уровня, на заведомо открытой клетке
    // (см. SPAWN_CELL_INDEX выше) - уже стоя на полу (не падая). Мировые
    // координаты этой клетки уже посчитаны build_level_cache() выше,
    // читаем их прямо из кэша вместо повторного счёта.
    phys_set_player_pos(
        cellCenterXLow[SPAWN_CELL_INDEX], cellCenterXHigh[SPAWN_CELL_INDEX],
        PLAYER_SPAWN_Y, 0,
        cellCenterZLow[SPAWN_CELL_INDEX], cellCenterZHigh[SPAWN_CELL_INDEX]);
    phys_step(0, 0, 0, 0, 0, 0);   // один шаг физики - подтвердить GROUNDED до первого кадра рендера

    poke(GPU3D_CAM_X_LOW, physPlayerXLow); poke(GPU3D_CAM_X_HIGH, physPlayerXHigh);
    poke(GPU3D_CAM_Y_LOW, physPlayerYLow); poke(GPU3D_CAM_Y_HIGH, physPlayerYHigh);
    poke(GPU3D_CAM_Z_LOW, physPlayerZLow); poke(GPU3D_CAM_Z_HIGH, physPlayerZHigh);
    poke(GPU3D_CAM_YAW_LOW, 0); poke(GPU3D_CAM_YAW_HIGH, 0);
    poke(GPU3D_CAM_PITCH_LOW, 0); poke(GPU3D_CAM_PITCH_HIGH, 0);

    poke(VIDEOCARD_COMMAND, 1); // MODE_ON - см. SNOW3D.MC, прячет консоль автоматически
    poke(MOUSE_CONTROL, 1);

    // Прицел - '+' по центру, прозрачный фон поверх 3D (тот же приём,
    // что у снежинок в SNOW3D.MC) - рисуется один раз, 3D-рендер текстовый
    // слой не трогает, перерисовывать в цикле не нужно.
    poke(CONSOLE_VISIBLE, 1);
    clear_screen();
    print_char(CROSSHAIR_COL, CROSSHAIR_ROW, CROSSHAIR_CHAR);
    set_color(CROSSHAIR_COL, CROSSHAIR_ROW, CROSSHAIR_FG, BG_TRANSPARENT);

    running = 1;
    while (running == 1) {
        int keys;
        int fwLow; int fwHigh;
        int stLow; int stHigh;

        // Ctrl+Q - разовое действие, старая очередь Keyboard ей отлично
        // подходит (в отличие от непрерывного движения - см. KeyState.h).
        key = peek(KEYBOARD_DATA);
        if (key == KEY_CTRL_Q) { running = 0; }

        // Движение - через KeyState ("зажата ли стрелка ПРЯМО СЕЙЧАС"),
        // не через очередь - плавно, без рывков, с диагоналями (см.
        // misty-zooming-bee.md).
        keys = peek(KEYSTATE);
        fwLow = 0; fwHigh = 0;
        stLow = 0; stHigh = 0;

        if (keys & KEYSTATE_UP) {
            add16(fwLow, fwHigh, MOVE_SPEED, 0);
            fwLow = mathResultLow; fwHigh = mathResultHigh;
        }
        if (keys & KEYSTATE_DOWN) {
            sub16(fwLow, fwHigh, MOVE_SPEED, 0);
            fwLow = mathResultLow; fwHigh = mathResultHigh;
        }
        if (keys & KEYSTATE_RIGHT) {
            add16(stLow, stHigh, MOVE_SPEED, 0);
            stLow = mathResultLow; stHigh = mathResultHigh;
        }
        if (keys & KEYSTATE_LEFT) {
            sub16(stLow, stHigh, MOVE_SPEED, 0);
            stLow = mathResultLow; stHigh = mathResultHigh;
        }

        compute_move_delta(fwLow, fwHigh, stLow, stHigh);
        update_mouse_look();

        // Гравитация - забота Phys3D (см. step()), тут только желаемое
        // горизонтальное смещение; результат (с учётом коллизий с
        // кубами/полом) - в GPU3D_CAM_*.
        phys_step(moveDeltaXLow, moveDeltaXHigh, 0, 0, moveDeltaZLow, moveDeltaZHigh);
        poke(GPU3D_CAM_X_LOW, physPlayerXLow); poke(GPU3D_CAM_X_HIGH, physPlayerXHigh);
        poke(GPU3D_CAM_Y_LOW, physPlayerYLow); poke(GPU3D_CAM_Y_HIGH, physPlayerYHigh);
        poke(GPU3D_CAM_Z_LOW, physPlayerZLow); poke(GPU3D_CAM_Z_HIGH, physPlayerZHigh);

        draw_floor();

        wait_ms(17); // ~60 кадров/сек
    }

    poke(MOUSE_CONTROL, 0);
    poke(VIDEOCARD_COMMAND, 2); // MODE_OFF
    clear_screen();

    return 0;
}
