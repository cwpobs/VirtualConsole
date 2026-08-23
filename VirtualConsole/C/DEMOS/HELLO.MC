// HELLO.MC - простейший пример на Мини-C: очищает экран, печатает
// "Hello world", ждёт нажатия любой клавиши и завершается.
//
// KEYBOARD_CONTROL (бит HAS_DATA=2) проверяется ДО чтения
// KEYBOARD_DATA - иначе "клавиш нет" и "нажата клавиша со значением 0"
// неотличимы (оба дают 0 при простом peek(KEYBOARD_DATA)) - см.
// C/TOOLS/EDIT.MC, где это разобрано подробно.
//
// Собирается командой "build hello.mc", запускается как "hello".

int main() {
    int key;
    int haveKey;

    clear_screen();
    print_str(0, 0, "Hello world");

    haveKey = 0;
    while (haveKey == 0) {
        if ((peek(KEYBOARD_CONTROL) & 2) != 0) {
            key = peek(KEYBOARD_DATA);
            haveKey = 1;
        }
    }

    return 0;
}
