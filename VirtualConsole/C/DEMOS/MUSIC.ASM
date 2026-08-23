; ============================================================
; MUSIC.ASM - проигрывает трекерную музыку (SPACE_~1.MOD) через
; ModLoader + SoundCard. Запускается из шелла командой "exec music.asm".
;
; Имя файла - "SPACE_~1.MOD" (DOS-стиль 8.3 с "~1", как исходное
; "space_debris.mod" обрезалось бы в DOS/FM.MC - см. ASSEMBLY.md,
; "ModLoader"/"Disk": NAME-регистр диска всегда 8.3, длинное имя туда
; не помещалось бы и портило листинг/копирование в FM.MC).
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

    ; ---- ModLoader: LOAD "SPACE_~1.MOD" ----

    LDI A, 83    ; S
    STA 0xF0001020
    LDI A, 80    ; P
    STA 0xF0001021
    LDI A, 65    ; A
    STA 0xF0001022
    LDI A, 67    ; C
    STA 0xF0001023
    LDI A, 69    ; E
    STA 0xF0001024
    LDI A, 95    ; _
    STA 0xF0001025
    LDI A, 126   ; ~
    STA 0xF0001026
    LDI A, 49    ; 1
    STA 0xF0001027
    LDI A, 46    ; .
    STA 0xF0001028
    LDI A, 77    ; M
    STA 0xF0001029
    LDI A, 79    ; O
    STA 0xF000102A
    LDI A, 68    ; D
    STA 0xF000102B
    LDI A, 0
    STA 0xF000102C      ; и так далее NAME12-31 = 0

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
