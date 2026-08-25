// GEOM3D.MC - переиспользуемая библиотека мини-C для работы с единым
// 3D-устройством Gpu3D (ускоритель + свет + математический сопроцессор
// 16/32 бит - было три отдельных устройства Gpu3D/Light3D/MathUnit, слиты
// в одно по итогам живого тестирования производительности, см.
// misty-zooming-bee.md). Подключается через #include "GEOM3D.MC" (см.
// ASSEMBLY.md, "Мини-C").
//
// Как и раньше - адреса Gpu3D НЕ подмешаны компилятором в прелюдию
// (kDevicePrelude в Compiler.cpp содержит только общие устройства -
// Keyboard/Clock/VideoCard/ConsoleLayer/PngLoader/MapLoader/Mouse/
// MatrixLoader). Все константы объявлены здесь одним файлом - вложенные
// #include ВНУТРИ библиотеки не поддерживаются (Disk::build разворачивает
// #include только в самом верхнеуровневом .mc-файле).
//
// ВАЖНО про #include и глобальные переменные: это обычный мини-C текст,
// вставляемый ПЕРЕД кодом подключающего файла - если подключающая
// программа объявит переменную с тем же именем, что и здесь
// (mathResultLow и т.п.), это ошибка компиляции (повторное объявление),
// не тихая переприсвоение - используйте имена, начинающиеся с math*/
// gpu3d*, как "занятые" этой библиотекой.

// ---- Gpu3D - полный набор регистров (см. Gpu3D.h). База 0xF0001100,
// диапазон нарочно большой (256 байт) - есть запас под будущий рост. ----

const GPU3D_VX_LOW = 0xF0001100;
const GPU3D_VX_HIGH = 0xF0001101;
const GPU3D_VY_LOW = 0xF0001102;
const GPU3D_VY_HIGH = 0xF0001103;
const GPU3D_VZ_LOW = 0xF0001104;
const GPU3D_VZ_HIGH = 0xF0001105;
const GPU3D_VR = 0xF0001106;
const GPU3D_VG = 0xF0001107;
const GPU3D_VB = 0xF0001108;
const GPU3D_VNX = 0xF0001109;
const GPU3D_VNY = 0xF000110A;
const GPU3D_VNZ = 0xF000110B;
const GPU3D_VU = 0xF000110C;         // зарезервировано под текстуры
const GPU3D_VV = 0xF000110D;         // зарезервировано под текстуры
const GPU3D_VTEXTURE = 0xF000110E;   // зарезервировано под текстуры
const GPU3D_COMMAND = 0xF000110F;
const GPU3D_STATUS = 0xF0001110;
const GPU3D_CUBE_SIZE_LOW = 0xF0001111;
const GPU3D_CUBE_SIZE_HIGH = 0xF0001112;

const GPU3D_OBJ_X_LOW = 0xF0001113;
const GPU3D_OBJ_X_HIGH = 0xF0001114;
const GPU3D_OBJ_Y_LOW = 0xF0001115;
const GPU3D_OBJ_Y_HIGH = 0xF0001116;
const GPU3D_OBJ_Z_LOW = 0xF0001117;
const GPU3D_OBJ_Z_HIGH = 0xF0001118;
const GPU3D_OBJ_YAW_LOW = 0xF0001119;
const GPU3D_OBJ_YAW_HIGH = 0xF000111A;
const GPU3D_OBJ_PITCH_LOW = 0xF000111B;
const GPU3D_OBJ_PITCH_HIGH = 0xF000111C;
const GPU3D_OBJ_ROLL_LOW = 0xF000111D;
const GPU3D_OBJ_ROLL_HIGH = 0xF000111E;

const GPU3D_CAM_X_LOW = 0xF000111F;
const GPU3D_CAM_X_HIGH = 0xF0001120;
const GPU3D_CAM_Y_LOW = 0xF0001121;
const GPU3D_CAM_Y_HIGH = 0xF0001122;
const GPU3D_CAM_Z_LOW = 0xF0001123;
const GPU3D_CAM_Z_HIGH = 0xF0001124;
const GPU3D_CAM_YAW_LOW = 0xF0001125;
const GPU3D_CAM_YAW_HIGH = 0xF0001126;
const GPU3D_CAM_PITCH_LOW = 0xF0001127;
const GPU3D_CAM_PITCH_HIGH = 0xF0001128;

// Команды GPU3D_COMMAND
const GPU3D_CMD_SUBMIT_VERTEX = 1;
const GPU3D_CMD_DRAW_TRIANGLE = 2;
const GPU3D_CMD_CLEAR = 3;
const GPU3D_CMD_PRESENT = 4;
const GPU3D_CMD_DRAW_CUBE = 5;

// ---- свет (было отдельное устройство Light3D). Компоненты - fixed-point
// "/100" (100 = 1.0, знаковый байт: -100 записывается как 156 = 256-100,
// см. NORMAL_NEG_UNIT ниже) ----

const GPU3D_LIGHT_DIR_X = 0xF0001129;
const GPU3D_LIGHT_DIR_Y = 0xF000112A;
const GPU3D_LIGHT_DIR_Z = 0xF000112B;
const GPU3D_LIGHT_R = 0xF000112C;
const GPU3D_LIGHT_G = 0xF000112D;
const GPU3D_LIGHT_B = 0xF000112E;
const GPU3D_AMBIENT = 0xF000112F;

// Осевые нормали куба - только эти два значения и нужны (±1.0 по одной оси,
// 0 по двум другим). Актуально для ручной сборки треугольников
// (SUBMIT_VERTEX/DRAW_TRIANGLE) - DRAW_CUBE считает нормали сам.
const NORMAL_POS_UNIT = 100;   // +1.0
const NORMAL_NEG_UNIT = 156;   // -1.0 (256-100, знаковый байт)
const NORMAL_ZERO = 0;

// ---- математика 16 бит (было отдельное устройство MathUnit) ----

const MATH_A_LOW = 0xF0001138;
const MATH_A_HIGH = 0xF0001139;
const MATH_B_LOW = 0xF000113A;
const MATH_B_HIGH = 0xF000113B;
const MATH_COMMAND = 0xF000113C;
const MATH_STATUS = 0xF000113D;
const MATH_RESULT_LOW = 0xF000113E;
const MATH_RESULT_HIGH = 0xF000113F;

const MATH_OP_ADD = 1;
const MATH_OP_SUB = 2;
const MATH_OP_MUL = 3;
const MATH_OP_DIV = 4;
const MATH_OP_SIN = 5;
const MATH_OP_COS = 6;
const MATH_OP_SQRT = 7;

// ---- математика 32 бита (новое - "мощнее", см. misty-zooming-bee.md).
// Операнды/результат - 4 байта, little-endian (байт 0 - младший) ----

const MATH32_A0 = 0xF0001140;
const MATH32_A1 = 0xF0001141;
const MATH32_A2 = 0xF0001142;
const MATH32_A3 = 0xF0001143;
const MATH32_B0 = 0xF0001144;
const MATH32_B1 = 0xF0001145;
const MATH32_B2 = 0xF0001146;
const MATH32_B3 = 0xF0001147;
const MATH32_COMMAND = 0xF0001148;
const MATH32_STATUS = 0xF0001149;
const MATH32_RESULT0 = 0xF000114A;
const MATH32_RESULT1 = 0xF000114B;
const MATH32_RESULT2 = 0xF000114C;
const MATH32_RESULT3 = 0xF000114D;

const MATH32_OP_ADD = 1;
const MATH32_OP_SUB = 2;
const MATH32_OP_MUL = 3;
const MATH32_OP_DIV = 4;
const MATH32_OP_SQRT = 5;

// ---- обёртки над MathUnit (16 бит) - результат каждой операции ложится
// в глобальные mathResultLow/mathResultHigh, читать их сразу после
// вызова, до следующего использования математики. Мини-C функции
// возвращают только один int (8 бит) - поэтому 16-битный результат идёт
// через глобальные переменные, а не return (тот же приём, что и у
// остальных многобайтовых регистров этого проекта). ----

int mathResultLow;
int mathResultHigh;

int math_op2(int op, int aLow, int aHigh, int bLow, int bHigh) {
    poke(MATH_A_LOW, aLow);
    poke(MATH_A_HIGH, aHigh);
    poke(MATH_B_LOW, bLow);
    poke(MATH_B_HIGH, bHigh);
    poke(MATH_COMMAND, op);
    mathResultLow = peek(MATH_RESULT_LOW);
    mathResultHigh = peek(MATH_RESULT_HIGH);
    return 0;
}

int add16(int aLow, int aHigh, int bLow, int bHigh) {
    return math_op2(MATH_OP_ADD, aLow, aHigh, bLow, bHigh);
}

int sub16(int aLow, int aHigh, int bLow, int bHigh) {
    return math_op2(MATH_OP_SUB, aLow, aHigh, bLow, bHigh);
}

int mul16(int aLow, int aHigh, int bLow, int bHigh) {
    return math_op2(MATH_OP_MUL, aLow, aHigh, bLow, bHigh);
}

int div16(int aLow, int aHigh, int bLow, int bHigh) {
    return math_op2(MATH_OP_DIV, aLow, aHigh, bLow, bHigh);
}

// Угол (aLow/aHigh) - в градусах, тот же формат, что у GPU3D_CAM_YAW_*/
// OBJ_YAW_* (см. Gpu3D.cpp, transformAndProject). Результат - *100
// (100 = 1.0), в mathResultLow/High.
int sin16(int angleLow, int angleHigh) {
    return math_op2(MATH_OP_SIN, angleLow, angleHigh, 0, 0);
}

int cos16(int angleLow, int angleHigh) {
    return math_op2(MATH_OP_COS, angleLow, angleHigh, 0, 0);
}

// 0 - (low,high), через MathUnit (а не вручную) - гарантированно
// правильный знаковый результат для последующих ADD/SUB/MUL, без ручной
// возни с wraparound.
int neg16(int low, int high) {
    return math_op2(MATH_OP_SUB, 0, 0, low, high);
}

// ---- обёртки над математикой 32 бит - тот же приём, результат в
// mathResult32_0..3 (байт 0 - младший). Для координат/дистанций, которым
// тесно в 16 битах. ----

int mathResult32_0;
int mathResult32_1;
int mathResult32_2;
int mathResult32_3;

int math_op32(int op, int a0, int a1, int a2, int a3, int b0, int b1, int b2, int b3) {
    poke(MATH32_A0, a0); poke(MATH32_A1, a1); poke(MATH32_A2, a2); poke(MATH32_A3, a3);
    poke(MATH32_B0, b0); poke(MATH32_B1, b1); poke(MATH32_B2, b2); poke(MATH32_B3, b3);
    poke(MATH32_COMMAND, op);
    mathResult32_0 = peek(MATH32_RESULT0);
    mathResult32_1 = peek(MATH32_RESULT1);
    mathResult32_2 = peek(MATH32_RESULT2);
    mathResult32_3 = peek(MATH32_RESULT3);
    return 0;
}

int add32(int a0, int a1, int a2, int a3, int b0, int b1, int b2, int b3) {
    return math_op32(MATH32_OP_ADD, a0, a1, a2, a3, b0, b1, b2, b3);
}

int sub32(int a0, int a1, int a2, int a3, int b0, int b1, int b2, int b3) {
    return math_op32(MATH32_OP_SUB, a0, a1, a2, a3, b0, b1, b2, b3);
}

int mul32(int a0, int a1, int a2, int a3, int b0, int b1, int b2, int b3) {
    return math_op32(MATH32_OP_MUL, a0, a1, a2, a3, b0, b1, b2, b3);
}

int div32(int a0, int a1, int a2, int a3, int b0, int b1, int b2, int b3) {
    return math_op32(MATH32_OP_DIV, a0, a1, a2, a3, b0, b1, b2, b3);
}

int sqrt32(int a0, int a1, int a2, int a3) {
    return math_op32(MATH32_OP_SQRT, a0, a1, a2, a3, 0, 0, 0, 0);
}

// ---- draw_cube_at(centerX, centerY, centerZ, halfSize, r, g, b) - куб
// заданного размера с центром в мировых координатах (все параметры -
// пары low/high). Аппаратный примитив DRAW_CUBE (см. Gpu3D.cpp) сам
// строит 8 вершин/12 треугольников с осевыми нормалями и освещением -
// сигнатура функции та же, что была при ручной сборке через
// SUBMIT_VERTEX (см. git-историю этого файла), но тело теперь - всего
// ~12 poke() вместо 468 (36 вершин × 13 байт) - именно это было главной
// причиной тормозов демки с полом из кубов (см.
// misty-zooming-bee.md). Не вызывает CLEAR/PRESENT сама - это забота
// вызывающего кода (CLEAR один раз в начале кадра, PRESENT один раз в
// конце, после всех кубов). ----

int draw_cube_at(int cxLow, int cxHigh, int cyLow, int cyHigh, int czLow, int czHigh,
                  int halfLow, int halfHigh, int r, int g, int b) {
    poke(GPU3D_VX_LOW, cxLow); poke(GPU3D_VX_HIGH, cxHigh);
    poke(GPU3D_VY_LOW, cyLow); poke(GPU3D_VY_HIGH, cyHigh);
    poke(GPU3D_VZ_LOW, czLow); poke(GPU3D_VZ_HIGH, czHigh);
    poke(GPU3D_CUBE_SIZE_LOW, halfLow); poke(GPU3D_CUBE_SIZE_HIGH, halfHigh);
    poke(GPU3D_VR, r); poke(GPU3D_VG, g); poke(GPU3D_VB, b);
    poke(GPU3D_COMMAND, GPU3D_CMD_DRAW_CUBE);
    return 0;
}
