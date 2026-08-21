; ============================================================
; boot.asm - минимальный загрузчик VirtualConsole.
;
; Единственная задача: найти SHELL.ASM на диске C, собрать его
; (Disk.LOAD_SHELL, COMMAND=10 - грузит на фиксированный адрес
; 0x00003000, см. ASSEMBLY.md, "Disk") и передать ему управление
; через JMP (не CALL - SHELL.ASM дальше сам себе хозяин: сам ставит
; обработчик прерываний, сам крутит бесконечный цикл терминала).
;
; Вся "начинка" (баннер, shell, диски, cd/dir/type/exec/create/del/
; copy и т.д.) теперь живёт в SHELL.ASM на диске - его можно
; редактировать и просто перезапускать VM, без пересборки этого
; C++-проекта.
; ============================================================

    JMP main
    JMP irq_stub

main:

    ; ---- Записываем имя "SHELL.ASM" в регистры NAME диска C ----

    LDI A, 83    ; 'S'
    STA 0xF00007E6
    LDI A, 72    ; 'H'
    STA 0xF00007E7
    LDI A, 69    ; 'E'
    STA 0xF00007E8
    LDI A, 76    ; 'L'
    STA 0xF00007E9
    LDI A, 76    ; 'L'
    STA 0xF00007EA
    LDI A, 46    ; '.'
    STA 0xF00007EB
    LDI A, 65    ; 'A'
    STA 0xF00007EC
    LDI A, 83    ; 'S'
    STA 0xF00007ED
    LDI A, 77    ; 'M'
    STA 0xF00007EE
    LDI A, 0
    STA 0xF00007EF
    STA 0xF00007F0
    STA 0xF00007F1

    LDI A, 10        ; DiskC COMMAND = LOAD_SHELL
    STA 0xF00007F2

    LDA 0xF00007F3   ; DiskC STATUS
    LDI B, 0
    CMP B
    JNZ boot_error

    JMP 0x00003000   ; передаём управление SHELL.ASM


boot_error:

    ; SHELL.ASM не найден на диске C или не собрался - выводим
    ; примитивное сообщение прямо в VRAM. Своей инфраструктуры для
    ; печати (print_char и т.д.) у boot.asm больше нет - это всё
    ; теперь в SHELL.ASM.

    LDHL 0xF0000007

    LDI A, 78    ; N
    STX
    INCHL
    LDI A, 79    ; O
    STX
    INCHL
    LDI A, 32
    STX
    INCHL
    LDI A, 83    ; S
    STX
    INCHL
    LDI A, 72    ; H
    STX
    INCHL
    LDI A, 69    ; E
    STX
    INCHL
    LDI A, 76    ; L
    STX
    INCHL
    LDI A, 76    ; L
    STX
    INCHL
    LDI A, 46    ; .
    STX
    INCHL
    LDI A, 65    ; A
    STX
    INCHL
    LDI A, 83    ; S
    STX
    INCHL
    LDI A, 77    ; M
    STX
    INCHL

    HLT


irq_stub:

    ; boot.asm никогда не вызывает EI, так что прерывание сюда не
    ; должно попасть - оставлено просто как безопасная заглушка.

    RETI
