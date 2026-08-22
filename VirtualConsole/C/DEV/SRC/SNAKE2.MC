// SNAKE2.MC - змейка на мини-C с псевдографикой и цветом (см.
// ASSEMBLY.md, "Мини-C", раздел "Экранные встроенные функции").
// Управление: W/A/S/D (любой регистр), выход - Ctrl+Q.
//
// В отличие от SNAKE.MC - никаких маппированных массивов на каждую
// строку экрана не нужно: print_char(x, y, ch)/set_color(x, y, fg, bg)
// сами умеют произвольный (x, y) в рантайме (компилятор сам считает
// y*80+x, избегая переполнения 8-битного MUL - см. ASSEMBLY.md). Вся
// остальная игровая логика (массивы тела змейки, движение сдвигом,
// рост, LCG для еды, опрос клавиатуры напрямую через peek(), пауза
// через Clock) - та же, что в SNAKE.MC.
//
// Собирается командой "build snake2.mc", запускается как "snake2".

const CLOCK_LOW = 0xF0000FFC;
const KEY_DATA = 0xF0000005;

const W = 32;   // ширина игрового поля в ячейках
const H = 14;   // высота игрового поля в ячейках

// Палитра - стандартная 16-цветная ANSI (см. ASSEMBLY.md, "TextAttr"):
// 0-7 обычные (чёрный/красный/зелёный/жёлтый/синий/пурпурный/голубой/
// белый), 8-15 - яркие версии тех же самых, в том же порядке.
const COLOR_BORDER = 14;   // ярко-голубой (было по ошибке 11 = ярко-жёлтый)
const COLOR_SNAKE  = 10;   // ярко-зелёный
const COLOR_FOOD   = 9;    // ярко-красный (было по ошибке 12 = ярко-синий)
const COLOR_TEXT   = 15;   // ярко-белый

int set_cell(int x, int y, int ch, int color) {
    print_char(x, y, ch);
    set_color(x, y, color, 0);
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

    set_cell(0, 0, 201, COLOR_BORDER);         // ╔
    set_cell(W - 1, 0, 187, COLOR_BORDER);     // ╗
    set_cell(0, H - 1, 200, COLOR_BORDER);     // ╚
    set_cell(W - 1, H - 1, 188, COLOR_BORDER); // ╝

    x = 1;
    while (x < W - 1) {
        set_cell(x, 0, 205, COLOR_BORDER);     // ═
        set_cell(x, H - 1, 205, COLOR_BORDER);
        x = x + 1;
    }

    y = 1;
    while (y < H - 1) {
        set_cell(0, y, 186, COLOR_BORDER);     // ║
        set_cell(W - 1, y, 186, COLOR_BORDER);
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
    print_char(7, H, d0 + 48);
    print_char(8, H, d1 + 48);
    print_char(9, H, d2 + 48);
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

    clear_screen();

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
        set_cell(snakeX[i], snakeY[i], 219, COLOR_SNAKE);   // █
        i = i + 1;
    }
    set_cell(foodX, foodY, 42, COLOR_FOOD);   // *

    print_str(0, H, "SCORE:");
    set_color(0, H, COLOR_TEXT, 0);
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
                    set_cell(foodX, foodY, 42, COLOR_FOOD);
                } else {
                    set_cell(tailX, tailY, 32, 0);
                }

                set_cell(headX, headY, 219, COLOR_SNAKE);
            }
        }

        wait_ms(120);
    }

    print_str(W + 2, 2, "GAME OVER");
    set_color(W + 2, 2, COLOR_FOOD, 0);
    wait_ms(200);
    wait_ms(200);
    wait_ms(200);
    wait_ms(200);
    wait_ms(200);

    return score;
}
