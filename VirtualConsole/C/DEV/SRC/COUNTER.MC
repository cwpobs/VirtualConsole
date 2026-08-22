// COUNTER.MC - демонстрация мини-C (см. ASSEMBLY.md, раздел
// "Мини-C"): функция, цикл, массив и poke() в Text VRAM в одной
// небольшой программе. Считает сумму чисел 1..10 через функцию
// sum() и печатает результат десятичным числом (3 цифры) в левый
// верхний угол экрана.
//
// Собирается командой "build counter.mc", запускается именем файла
// без расширения - "counter" - точно так же, как обычный .RUN,
// собранный из ассемблера (см. cmd_autorun в SHELL.ASM).

const VRAM = 0xF0000007;

int sum(int n) {
    int total;
    int i;
    total = 0;
    i = 1;
    while (i <= n) {
        total = total + i;
        i = i + 1;
    }
    return total;
}

int digits[3];

int main() {
    int result;
    result = sum(10);

    digits[0] = result / 100;
    digits[1] = (result / 10) % 10;
    digits[2] = result % 10;

    poke(VRAM + 0, digits[0] + 48);
    poke(VRAM + 1, digits[1] + 48);
    poke(VRAM + 2, digits[2] + 48);

    return result;
}
