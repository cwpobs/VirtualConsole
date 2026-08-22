// STRLIB.MC - переиспользуемая библиотека мини-C, подключаемая через
// #include "STRLIB.MC" (см. ASSEMBLY.md, "Мини-C"). Библиотеки лежат на
// диске C, в DEV/LIB - билдер (Disk::build()) ищет их там ВСЕГДА,
// независимо от того, с какого диска реально собирается сама программа.
// Это обычный Mini-C текст (const/функции) - не самостоятельная
// программа: у него нет main(), он не собирается сам по себе, только как
// часть чужого файла.
//
// print_number3(x, y, value) - печатает value (0-255) как 3 десятичные
// цифры на Text VRAM начиная с колонки x, строка y (тот же приём, что
// SNAKE.MC::show_score/COUNTER.MC, но как переиспользуемая функция).

int print_number3(int x, int y, int value) {
    int d0;
    int d1;
    int d2;
    d0 = value / 100;
    d1 = (value / 10) % 10;
    d2 = value % 10;
    print_char(x, y, d0 + 48);
    print_char(x + 1, y, d1 + 48);
    print_char(x + 2, y, d2 + 48);
    return 0;
}
