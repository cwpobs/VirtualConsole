// PHYS3D.MC - переиспользуемая библиотека мини-C для физического
// ускорителя Phys3D: гравитация, статичные AABB-боксы, коллизии игрока
// с ними и с бесконечной опорной плоскостью пола ("горизонт"). Отдельное
// устройство от Gpu3D (сознательно не связаны в этой версии - см.
// misty-zooming-bee.md). Подключается через #include "PHYS3D.MC" - в
// одном файле можно подключить несколько библиотек несколькими строками
// #include (см. ASSEMBLY.md, "Мини-C" - Disk::build разворачивает
// КАЖДУЮ строку с #include независимо).
//
// Как и GEOM3D.MC - адреса Phys3D не подмешаны компилятором в прелюдию
// (устройство не общего назначения). Не подключайте оба файла в одной
// программе, если не собираетесь пользоваться обоими - лишние глобали/
// функции не мешают компиляции, но раздувают бинарник впустую.

const PHYS_GROUND_Y_LOW = 0xF0001200;
const PHYS_GROUND_Y_HIGH = 0xF0001201;
const PHYS_GRAVITY_LOW = 0xF0001202;
const PHYS_GRAVITY_HIGH = 0xF0001203;

const PHYS_BOX_SLOT = 0xF0001204;
const PHYS_BOX_X_LOW = 0xF0001205;
const PHYS_BOX_X_HIGH = 0xF0001206;
const PHYS_BOX_Y_LOW = 0xF0001207;
const PHYS_BOX_Y_HIGH = 0xF0001208;
const PHYS_BOX_Z_LOW = 0xF0001209;
const PHYS_BOX_Z_HIGH = 0xF000120A;
const PHYS_BOX_HALF_X = 0xF000120B;
const PHYS_BOX_HALF_Y = 0xF000120C;
const PHYS_BOX_HALF_Z = 0xF000120D;
const PHYS_BOX_COMMAND = 0xF000120E;
const PHYS_BOX_STATUS = 0xF000120F;

// Игрок - сфера (см. Phys3D.h) - смещения 17-18 (бывшие
// PLAYER_HALF_Y/Z) сейчас не заняты ничем.
const PHYS_PLAYER_RADIUS = 0xF0001210;
const PHYS_PLAYER_X_LOW = 0xF0001213;
const PHYS_PLAYER_X_HIGH = 0xF0001214;
const PHYS_PLAYER_Y_LOW = 0xF0001215;
const PHYS_PLAYER_Y_HIGH = 0xF0001216;
const PHYS_PLAYER_Z_LOW = 0xF0001217;
const PHYS_PLAYER_Z_HIGH = 0xF0001218;

const PHYS_MOVE_DX_LOW = 0xF0001219;
const PHYS_MOVE_DX_HIGH = 0xF000121A;
const PHYS_MOVE_DY_LOW = 0xF000121B;
const PHYS_MOVE_DY_HIGH = 0xF000121C;
const PHYS_MOVE_DZ_LOW = 0xF000121D;
const PHYS_MOVE_DZ_HIGH = 0xF000121E;

const PHYS_GROUNDED = 0xF000121F;
const PHYS_STEP_COMMAND = 0xF0001220;
const PHYS_STEP_STATUS = 0xF0001221;

const PHYS_BOX_CMD_DEFINE = 1;
const PHYS_BOX_CMD_CLEAR_ALL = 2;
const PHYS_STEP_CMD_STEP = 1;

// Определяет статичный AABB-бокс-коллайдер в слоте slot (0-127) - вызвать
// ОДИН РАЗ при загрузке уровня для каждого физического кубика (не за
// кадр - см. заголовок файла про то, почему). center*/half* - мировые
// координаты/полуразмеры (те же единицы, что у Gpu3D).
int phys_define_box(int slot, int cxLow, int cxHigh, int cyLow, int cyHigh,
                     int czLow, int czHigh, int halfX, int halfY, int halfZ) {
    poke(PHYS_BOX_SLOT, slot);
    poke(PHYS_BOX_X_LOW, cxLow); poke(PHYS_BOX_X_HIGH, cxHigh);
    poke(PHYS_BOX_Y_LOW, cyLow); poke(PHYS_BOX_Y_HIGH, cyHigh);
    poke(PHYS_BOX_Z_LOW, czLow); poke(PHYS_BOX_Z_HIGH, czHigh);
    poke(PHYS_BOX_HALF_X, halfX);
    poke(PHYS_BOX_HALF_Y, halfY);
    poke(PHYS_BOX_HALF_Z, halfZ);
    poke(PHYS_BOX_COMMAND, PHYS_BOX_CMD_DEFINE);
    return peek(PHYS_BOX_STATUS);
}

int phys_clear_boxes() {
    poke(PHYS_BOX_COMMAND, PHYS_BOX_CMD_CLEAR_ALL);
    return 0;
}

// Задаёт позицию игрока НАПРЯМУЮ, без проверки коллизий - для спавна/
// телепорта (см. Phys3D.h - как OBJ_X у Gpu3D).
int phys_set_player_pos(int xLow, int xHigh, int yLow, int yHigh, int zLow, int zHigh) {
    poke(PHYS_PLAYER_X_LOW, xLow); poke(PHYS_PLAYER_X_HIGH, xHigh);
    poke(PHYS_PLAYER_Y_LOW, yLow); poke(PHYS_PLAYER_Y_HIGH, yHigh);
    poke(PHYS_PLAYER_Z_LOW, zLow); poke(PHYS_PLAYER_Z_HIGH, zHigh);
    return 0;
}

// Двигает игрока на желаемое (dx,dy,dz) за этот кадр, разрешая коллизии
// с боксами и полом (плюс гравитация - см. Phys3D.cpp, step()).
// Результат - в physPlayerX/Y/ZLow/High и physGrounded (глобальные,
// читать сразу после вызова).
int physPlayerXLow; int physPlayerXHigh;
int physPlayerYLow; int physPlayerYHigh;
int physPlayerZLow; int physPlayerZHigh;
int physGrounded;

int phys_step(int dxLow, int dxHigh, int dyLow, int dyHigh, int dzLow, int dzHigh) {
    poke(PHYS_MOVE_DX_LOW, dxLow); poke(PHYS_MOVE_DX_HIGH, dxHigh);
    poke(PHYS_MOVE_DY_LOW, dyLow); poke(PHYS_MOVE_DY_HIGH, dyHigh);
    poke(PHYS_MOVE_DZ_LOW, dzLow); poke(PHYS_MOVE_DZ_HIGH, dzHigh);
    poke(PHYS_STEP_COMMAND, PHYS_STEP_CMD_STEP);

    physPlayerXLow = peek(PHYS_PLAYER_X_LOW); physPlayerXHigh = peek(PHYS_PLAYER_X_HIGH);
    physPlayerYLow = peek(PHYS_PLAYER_Y_LOW); physPlayerYHigh = peek(PHYS_PLAYER_Y_HIGH);
    physPlayerZLow = peek(PHYS_PLAYER_Z_LOW); physPlayerZHigh = peek(PHYS_PLAYER_Z_HIGH);
    physGrounded = peek(PHYS_GROUNDED);

    return peek(PHYS_STEP_STATUS);
}
