// LIBDEMO.MC - минимальный пример #include: подключает C/DEV/LIB/STRLIB.MC
// и вызывает его print_number3() - показывает, что механизм #include
// (см. Disk::build()/ASSEMBLY.md, "Мини-C") реально работает, а не только
// собственные встроенные константы устройств.
//
// Собирается командой "build libdemo.mc", запускается как "libdemo".

#include "STRLIB.MC"

int main() {
    clear_screen();
    print_str(0, 0, "print_number3 via #include:");
    print_number3(0, 1, 7);
    print_number3(4, 1, 42);
    print_number3(8, 1, 255);
    return 0;
}
