// SNAKE.MC - классическая змейка на мини-C (см. ASSEMBLY.md, раздел
// "Мини-C"). Управление: W/A/S/D (любой регистр), выход - Ctrl+Q.
//
// Игровое поле замаплено прямо на Text VRAM - по одному массиву на
// строку экрана (row0..row13), см. ASSEMBLY.md про маппированные
// массивы ("int имя[размер] = адрес;"): индекс arr[i] - обычный int
// (8 бит), а строка Text VRAM линейно (y*80+x) вылезает за 255 уже
// на 4-й строке поля - поэтому один массив на строку, а не один
// большой массив на всё поле.
//
// Клавиатура читается НАПРЯМУЮ через peek(0xF0000005) (регистр DATA),
// а не через общую переменную SHELL.ASM lastKey - у мини-C нет EI, а
// dispatch_command (и, значит, exec/run) выполняется с выключенными
// прерываниями, так что lastKey всё равно не обновлялся бы.
//
// Собирается командой "build snake.mc", запускается как "snake".

const VRAM = 0xF0000007;
const CLOCK_LOW = 0xF0000FFC;
const KEY_DATA = 0xF0000005;

const W = 32;   // ширина игрового поля в ячейках
const H = 14;   // высота игрового поля в ячейках

int row0[32]  = 0xF0000007 + 80*1;
int row1[32]  = 0xF0000007 + 80*2;
int row2[32]  = 0xF0000007 + 80*3;
int row3[32]  = 0xF0000007 + 80*4;
int row4[32]  = 0xF0000007 + 80*5;
int row5[32]  = 0xF0000007 + 80*6;
int row6[32]  = 0xF0000007 + 80*7;
int row7[32]  = 0xF0000007 + 80*8;
int row8[32]  = 0xF0000007 + 80*9;
int row9[32]  = 0xF0000007 + 80*10;
int row10[32] = 0xF0000007 + 80*11;
int row11[32] = 0xF0000007 + 80*12;
int row12[32] = 0xF0000007 + 80*13;
int row13[32] = 0xF0000007 + 80*14;

int set_cell(int x, int y, int ch) {
    if (y == 0)  { row0[x]  = ch; return 0; }
    if (y == 1)  { row1[x]  = ch; return 0; }
    if (y == 2)  { row2[x]  = ch; return 0; }
    if (y == 3)  { row3[x]  = ch; return 0; }
    if (y == 4)  { row4[x]  = ch; return 0; }
    if (y == 5)  { row5[x]  = ch; return 0; }
    if (y == 6)  { row6[x]  = ch; return 0; }
    if (y == 7)  { row7[x]  = ch; return 0; }
    if (y == 8)  { row8[x]  = ch; return 0; }
    if (y == 9)  { row9[x]  = ch; return 0; }
    if (y == 10) { row10[x] = ch; return 0; }
    if (y == 11) { row11[x] = ch; return 0; }
    if (y == 12) { row12[x] = ch; return 0; }
    row13[x] = ch;
    return 0;
}

int wait_ms(int ms) {
    poke(CLOCK_LOW, 0);
    while (peek(CLOCK_LOW) < ms) {
    }
    return 0;
}

int snakeX[200];
int snakeY[200];
int length;
int dir;        // 0=вверх 1=вниз 2=влево 3=вправо
int foodX;
int foodY;
int score;
int seed;
int running;

int rand_next() {
    seed = seed * 109 + 71;
    return seed;
}

int place_food() {
    int ok;
    int i;
    int fx;
    int fy;
    ok = 0;
    while (ok == 0) {
        fx = 1 + (rand_next() % (W - 2));
        fy = 1 + (rand_next() % (H - 2));
        ok = 1;
        i = 0;
        while (i < length) {
            if (snakeX[i] == fx) {
                if (snakeY[i] == fy) {
                    ok = 0;
                }
            }
            i = i + 1;
        }
    }
    foodX = fx;
    foodY = fy;
    return 0;
}

int draw_borders() {
    int x;
    int y;
    x = 0;
    while (x < W) {
        set_cell(x, 0, 35);        // '#'
        set_cell(x, H - 1, 35);
        x = x + 1;
    }
    y = 0;
    while (y < H) {
        set_cell(0, y, 35);
        set_cell(W - 1, y, 35);
        y = y + 1;
    }
    return 0;
}

int show_score() {
    int d0;
    int d1;
    int d2;
    int s;
    s = score;
    d0 = s / 100;
    d1 = (s / 10) % 10;
    d2 = s % 10;
    poke(VRAM + 7, d0 + 48);
    poke(VRAM + 8, d1 + 48);
    poke(VRAM + 9, d2 + 48);
    return 0;
}

int show_game_over() {
    poke(VRAM + 0, 71);   // G
    poke(VRAM + 1, 65);   // A
    poke(VRAM + 2, 77);   // M
    poke(VRAM + 3, 69);   // E
    poke(VRAM + 4, 32);
    poke(VRAM + 5, 79);   // O
    poke(VRAM + 6, 86);   // V
    poke(VRAM + 7, 69);   // E
    poke(VRAM + 8, 82);   // R
    return 0;
}

int main() {
    int i;
    int key;
    int headX;
    int headY;
    int tailX;
    int tailY;
    int grew;

    seed = peek(CLOCK_LOW) + 1;

    length = 3;
    snakeX[0] = 10;
    snakeY[0] = 7;
    snakeX[1] = 9;
    snakeY[1] = 7;
    snakeX[2] = 8;
    snakeY[2] = 7;
    dir = 3;
    score = 0;
    running = 1;

    draw_borders();
    place_food();

    i = 0;
    while (i < length) {
        set_cell(snakeX[i], snakeY[i], 79);   // 'O'
        i = i + 1;
    }
    set_cell(foodX, foodY, 42);   // '*'

    poke(VRAM + 0, 83);   // S
    poke(VRAM + 1, 67);   // C
    poke(VRAM + 2, 79);   // O
    poke(VRAM + 3, 82);   // R
    poke(VRAM + 4, 69);   // E
    poke(VRAM + 5, 58);   // :
    poke(VRAM + 6, 32);
    show_score();

    while (running == 1) {
        key = peek(KEY_DATA);

        if (key == 17) { running = 0; }

        if (key == 119) { if (dir != 1) { dir = 0; } }
        if (key == 87)  { if (dir != 1) { dir = 0; } }
        if (key == 115) { if (dir != 0) { dir = 1; } }
        if (key == 83)  { if (dir != 0) { dir = 1; } }
        if (key == 97)  { if (dir != 3) { dir = 2; } }
        if (key == 65)  { if (dir != 3) { dir = 2; } }
        if (key == 100) { if (dir != 2) { dir = 3; } }
        if (key == 68)  { if (dir != 2) { dir = 3; } }

        if (running == 1) {
            headX = snakeX[0];
            headY = snakeY[0];
            if (dir == 0) { headY = headY - 1; }
            if (dir == 1) { headY = headY + 1; }
            if (dir == 2) { headX = headX - 1; }
            if (dir == 3) { headX = headX + 1; }

            if (headX <= 0)     { running = 0; }
            if (headX >= W - 1) { running = 0; }
            if (headY <= 0)     { running = 0; }
            if (headY >= H - 1) { running = 0; }

            if (running == 1) {
                i = 0;
                while (i < length) {
                    if (snakeX[i] == headX) {
                        if (snakeY[i] == headY) {
                            running = 0;
                        }
                    }
                    i = i + 1;
                }
            }

            if (running == 1) {
                tailX = snakeX[length - 1];
                tailY = snakeY[length - 1];

                i = length - 1;
                while (i > 0) {
                    snakeX[i] = snakeX[i - 1];
                    snakeY[i] = snakeY[i - 1];
                    i = i - 1;
                }
                snakeX[0] = headX;
                snakeY[0] = headY;

                grew = 0;
                if (headX == foodX) {
                    if (headY == foodY) {
                        grew = 1;
                    }
                }

                if (grew == 1) {
                    score = score + 1;
                    if (length < 199) {
                        snakeX[length] = tailX;
                        snakeY[length] = tailY;
                        length = length + 1;
                    }
                    show_score();
                    place_food();
                    set_cell(foodX, foodY, 42);
                } else {
                    set_cell(tailX, tailY, 32);
                }

                set_cell(headX, headY, 79);
            }
        }

        wait_ms(120);
    }

    show_game_over();
    wait_ms(200);
    wait_ms(200);
    wait_ms(200);
    wait_ms(200);
    wait_ms(200);

    return score;
}
