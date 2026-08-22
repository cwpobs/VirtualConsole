; ============================================================
; MUSIC.ASM - проигрывает трекерную музыку (space_debris.mod) через
; ModLoader + SoundCard. Запускается из шелла командой "exec music.asm".
;
; ModLoader разбирает .mod-файл (формат ProTracker - см. ASSEMBLY.md,
; "ModLoader") и кладёт его в SoundCard, которая дальше играет песню
; целиком в фоновом аудио-потоке (секвенсор+микшер+вывод звука) -
; программе самой почти нечего делать, кроме ожидания Ctrl+Q.
;
; Ctrl+Q ведёт себя как везде в системе - завершает всю VM (см.
; SHELL.ASM/irq_handler). EI нужен по той же причине, что и в
; DEMO.ASM/SPRITES.ASM/TILEDEMO.ASM - без него клавиатурное прерывание
; не сработает во время цикла (dispatch_command вызывается с
; прерываниями выключенными - см. CPU::step).
; ============================================================

    EI

    ; ---- ModLoader: LOAD "space_debris.mod" ----

    LDI A, 115   ; s
    STA 0xF0001020
    LDI A, 112   ; p
    STA 0xF0001021
    LDI A, 97    ; a
    STA 0xF0001022
    LDI A, 99    ; c
    STA 0xF0001023
    LDI A, 101   ; e
    STA 0xF0001024
    LDI A, 95    ; _
    STA 0xF0001025
    LDI A, 100   ; d
    STA 0xF0001026
    LDI A, 101   ; e
    STA 0xF0001027
    LDI A, 98    ; b
    STA 0xF0001028
    LDI A, 114   ; r
    STA 0xF0001029
    LDI A, 105   ; i
    STA 0xF000102A
    LDI A, 115   ; s
    STA 0xF000102B
    LDI A, 46    ; .
    STA 0xF000102C
    LDI A, 109   ; m
    STA 0xF000102D
    LDI A, 111   ; o
    STA 0xF000102E
    LDI A, 100   ; d
    STA 0xF000102F
    LDI A, 0
    STA 0xF0001030      ; и так далее NAME16-31 = 0

    LDI A, 1
    STA 0xF0001040      ; ModLoader COMMAND = LOAD

    LDA 0xF0001041       ; ModLoader STATUS
    LDI B, 0
    CMP B
    JNZ music_error

    ; ---- SoundCard: PLAY ----

    LDI A, 1
    STA 0xF0001066      ; SoundCard COMMAND = PLAY


music_loop:

    LDA 0x00010001      ; lastKey
    LDI B, 17           ; Ctrl+Q
    CMP B
    JNZ music_loop

    LDI A, 2
    STA 0xF0001066      ; SoundCard COMMAND = STOP


music_error:

    DI

    RET
