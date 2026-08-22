// MUSIC2.MC - проигрывает трекерную музыку (space_debris.mod) через
// новые команды Мини-C (mod_load()/sound_play()/sound_stop() - см.
// ASSEMBLY.md, "Мини-C") И ОДНОВРЕМЕННО рисует визуализацию в
// графическом режиме VideoCard - 4 столбика-эквалайзера, по одному на
// канал ProTracker, высота которых читается прямо из новых регистров
// SoundCard (CHANNEL0-3_VOLUME, 0xF0001069-0xF000106C) через
// маппированный массив channelVol[4] - как игровое поле в SNAKE.MC.
//
// VideoCard (графика) и SoundCard (звук) - независимые устройства со
// своими собственными потоками (см. ASSEMBLY.md, разделы "VideoCard"/
// "SoundCard") - работают вместе без специальных ухищрений.
//
// Собирается командой "build music2.mc", запускается как "music2".
// Выход - Ctrl+Q.

const KEY_DATA = 0xF0000005;
const CLOCK_LOW = 0xF0000FFC;

const VIDEO_X = 0xF0000FDE;
const VIDEO_X_HIGH = 0xF0000FDF;
const VIDEO_Y = 0xF0000FE0;
const VIDEO_Y_HIGH = 0xF0000FE1;
const VIDEO_W = 0xF0000FE2;
const VIDEO_W_HIGH = 0xF0000FE3;
const VIDEO_H = 0xF0000FE4;
const VIDEO_H_HIGH = 0xF0000FE5;
const VIDEO_R = 0xF0000FE6;
const VIDEO_G = 0xF0000FE7;
const VIDEO_B = 0xF0000FE8;
const VIDEO_COMMAND = 0xF0000FE9;

// Маппированный массив на новые регистры SoundCard (см. ASSEMBLY.md,
// "SoundCard") - громкость каналов 0-64, read-only, обновляется
// секвенсором сама по себе, без какой-либо команды с нашей стороны.
int channelVol[4] = 0xF0001069;

int wait_ms(int ms) {
    poke(CLOCK_LOW, 0);
    while (peek(CLOCK_LOW) < ms) {
    }
    return 0;
}

int draw_bar(int x, int vol, int r, int g, int b) {
    // Столбик растёт вверх от базовой линии y=220 - высота
    // пропорциональна громкости канала (0-64 -> 0-192 пикселей,
    // *3 - подобрано, чтобы влезать в экран 320x240 с запасом).
    int height;
    int y;

    height = vol * 3;
    y = 220 - height;

    poke(VIDEO_X, x);
    poke(VIDEO_X_HIGH, 0);
    poke(VIDEO_Y, y);
    poke(VIDEO_Y_HIGH, 0);
    poke(VIDEO_W, 40);
    poke(VIDEO_W_HIGH, 0);
    poke(VIDEO_H, height);
    poke(VIDEO_H_HIGH, 0);
    poke(VIDEO_R, r);
    poke(VIDEO_G, g);
    poke(VIDEO_B, b);
    poke(VIDEO_COMMAND, 5);   // FILL_RECT

    return 0;
}

int main() {
    int key;
    int running;

    if (mod_load("space_debris.mod") != 0) {
        return 1;   // файл не найден/неподдерживаемый формат - тихо выходим
    }
    sound_play();

    poke(VIDEO_COMMAND, 1);   // MODE_ON - открыть графическое окно

    running = 1;
    while (running == 1) {
        key = peek(KEY_DATA);
        if (key == 17) { running = 0; }   // Ctrl+Q

        poke(VIDEO_R, 0);
        poke(VIDEO_G, 0);
        poke(VIDEO_B, 0);
        poke(VIDEO_COMMAND, 3);   // CLEAR (игнорирует X/Y/W/H, только R/G/B)

        draw_bar(20,  channelVol[0], 255, 60, 60);    // канал 0 - красный
        draw_bar(90,  channelVol[1], 60, 255, 60);    // канал 1 - зелёный
        draw_bar(160, channelVol[2], 60, 60, 255);    // канал 2 - синий
        draw_bar(230, channelVol[3], 255, 255, 60);   // канал 3 - жёлтый

        wait_ms(33);   // ~30 кадров/сек
    }

    sound_stop();
    poke(VIDEO_COMMAND, 2);   // MODE_OFF

    return 0;
}
