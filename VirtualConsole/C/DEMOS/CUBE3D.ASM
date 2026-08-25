; ============================================================
; CUBE3D.ASM - демо 3D-ускорителя (Gpu3D): вращающийся цветной куб +
; UI-спрайт поверх (иконка из SPRITES.PNG, всегда видна независимо от
; того, что происходит с гранями куба под ней - см. ASSEMBLY.md,
; "VideoCard" про порядок слоёв - спрайты всегда самые верхние).
; Запускается из шелла командой "exec cube3d.asm".
;
; Вся 3D-математика (модель/камера/проекция/растеризация/z-буфер) -
; на стороне C++ внутри Gpu3D - ассемблеру видны только "вот вершина"/
; "нарисуй треугольник"/"покажи кадр" (см. ASSEMBLY.md, "Gpu3D").
;
; Ctrl+Q ведёт себя как везде в системе - завершает всю VM. EI нужен
; по той же причине, что и в DEMO.ASM/SPRITES.ASM/TILEDEMO.ASM/
; MUSIC.ASM - без него клавиатурное прерывание не сработает во время
; цикла (dispatch_command вызывается с прерываниями выключенными -
; см. CPU::step).
; ============================================================

    EI

    ; ---- камера: смотрит на куб издалека ----

    LDI A, 106
    STA 0xF0001123      ; CAM_Z_LOW  (-150, см. combine())
    LDI A, 255
    STA 0xF0001124      ; CAM_Z_HIGH

    ; ---- UI-спрайт (иконка) поверх сцены ----

    LDI A, 83    ; S
    STA 0xF0000FFE
    LDI A, 80    ; P
    STA 0xF0000FFF
    LDI A, 82    ; R
    STA 0xF0001000
    LDI A, 73    ; I
    STA 0xF0001001
    LDI A, 84    ; T
    STA 0xF0001002
    LDI A, 69    ; E
    STA 0xF0001003
    LDI A, 83    ; S
    STA 0xF0001004
    LDI A, 46    ; .
    STA 0xF0001005
    LDI A, 80    ; P
    STA 0xF0001006
    LDI A, 78    ; N
    STA 0xF0001007
    LDI A, 71    ; G
    STA 0xF0001008
    LDI A, 0
    STA 0xF0001009

    LDI A, 1
    STA 0xF000100F      ; PngLoader COMMAND = LOAD

    LDA 0xF0001010       ; PngLoader STATUS
    LDI B, 0
    CMP B
    JNZ cube3d_no_sprite ; спрайтшит не нашёлся - едем дальше без UI-иконки

    LDI A, 0
    STA 0xF000100A      ; SRC_X_LOW = 0
    STA 0xF000100B
    STA 0xF000100C      ; SRC_Y_LOW = 0
    STA 0xF000100D
    STA 0xF000100E      ; PngLoader SPRITE_INDEX = 0
    LDI A, 2
    STA 0xF000100F      ; COMMAND = EXTRACT

    LDI A, 0
    STA 0xF0000FEB      ; VideoCard SPRITE_INDEX = 0
    LDI A, 10
    STA 0xF0000FEE      ; SPRITE_X_LOW = 10
    LDI A, 0
    STA 0xF0000FEF
    LDI A, 10
    STA 0xF0000FF0      ; SPRITE_Y_LOW = 10
    LDI A, 0
    STA 0xF0000FF1
    LDI A, 1
    STA 0xF0000FF2      ; SPRITE_VISIBLE = 1

cube3d_no_sprite:

    ; ---- открыть видеокарту ----

    LDI A, 1
    STA 0xF0000FE9      ; VideoCard COMMAND = MODE_ON

    LDI A, 0
    STA 0xF0001119      ; OBJ_YAW_LOW = 0
    STA 0xF000111A      ; OBJ_YAW_HIGH = 0


cube3d_loop:

    LDA 0x00010001      ; lastKey
    LDI B, 17           ; Ctrl+Q
    CMP B
    JZ cube3d_exit

    LDI A, 3
    STA 0xF000110F      ; Gpu3D COMMAND = CLEAR

    ; ---- 12 треугольников (6 граней куба) ----

    CALL v0
    CALL c_red
    LDI A, 1
    STA 0xF000110F
    CALL v1
    CALL c_red
    LDI A, 1
    STA 0xF000110F
    CALL v2
    CALL c_red
    LDI A, 1
    STA 0xF000110F
    LDI A, 2
    STA 0xF000110F      ; грань -Z, треугольник 1

    CALL v0
    CALL c_red
    LDI A, 1
    STA 0xF000110F
    CALL v2
    CALL c_red
    LDI A, 1
    STA 0xF000110F
    CALL v3
    CALL c_red
    LDI A, 1
    STA 0xF000110F
    LDI A, 2
    STA 0xF000110F      ; грань -Z, треугольник 2

    CALL v4
    CALL c_green
    LDI A, 1
    STA 0xF000110F
    CALL v5
    CALL c_green
    LDI A, 1
    STA 0xF000110F
    CALL v6
    CALL c_green
    LDI A, 1
    STA 0xF000110F
    LDI A, 2
    STA 0xF000110F      ; грань +Z, треугольник 1

    CALL v4
    CALL c_green
    LDI A, 1
    STA 0xF000110F
    CALL v6
    CALL c_green
    LDI A, 1
    STA 0xF000110F
    CALL v7
    CALL c_green
    LDI A, 1
    STA 0xF000110F
    LDI A, 2
    STA 0xF000110F      ; грань +Z, треугольник 2

    CALL v0
    CALL c_blue
    LDI A, 1
    STA 0xF000110F
    CALL v1
    CALL c_blue
    LDI A, 1
    STA 0xF000110F
    CALL v5
    CALL c_blue
    LDI A, 1
    STA 0xF000110F
    LDI A, 2
    STA 0xF000110F      ; грань -Y, треугольник 1

    CALL v0
    CALL c_blue
    LDI A, 1
    STA 0xF000110F
    CALL v5
    CALL c_blue
    LDI A, 1
    STA 0xF000110F
    CALL v4
    CALL c_blue
    LDI A, 1
    STA 0xF000110F
    LDI A, 2
    STA 0xF000110F      ; грань -Y, треугольник 2

    CALL v3
    CALL c_yellow
    LDI A, 1
    STA 0xF000110F
    CALL v2
    CALL c_yellow
    LDI A, 1
    STA 0xF000110F
    CALL v6
    CALL c_yellow
    LDI A, 1
    STA 0xF000110F
    LDI A, 2
    STA 0xF000110F      ; грань +Y, треугольник 1

    CALL v3
    CALL c_yellow
    LDI A, 1
    STA 0xF000110F
    CALL v6
    CALL c_yellow
    LDI A, 1
    STA 0xF000110F
    CALL v7
    CALL c_yellow
    LDI A, 1
    STA 0xF000110F
    LDI A, 2
    STA 0xF000110F      ; грань +Y, треугольник 2

    CALL v0
    CALL c_magenta
    LDI A, 1
    STA 0xF000110F
    CALL v4
    CALL c_magenta
    LDI A, 1
    STA 0xF000110F
    CALL v7
    CALL c_magenta
    LDI A, 1
    STA 0xF000110F
    LDI A, 2
    STA 0xF000110F      ; грань -X, треугольник 1

    CALL v0
    CALL c_magenta
    LDI A, 1
    STA 0xF000110F
    CALL v7
    CALL c_magenta
    LDI A, 1
    STA 0xF000110F
    CALL v3
    CALL c_magenta
    LDI A, 1
    STA 0xF000110F
    LDI A, 2
    STA 0xF000110F      ; грань -X, треугольник 2

    CALL v1
    CALL c_cyan
    LDI A, 1
    STA 0xF000110F
    CALL v2
    CALL c_cyan
    LDI A, 1
    STA 0xF000110F
    CALL v6
    CALL c_cyan
    LDI A, 1
    STA 0xF000110F
    LDI A, 2
    STA 0xF000110F      ; грань +X, треугольник 1

    CALL v1
    CALL c_cyan
    LDI A, 1
    STA 0xF000110F
    CALL v6
    CALL c_cyan
    LDI A, 1
    STA 0xF000110F
    CALL v5
    CALL c_cyan
    LDI A, 1
    STA 0xF000110F
    LDI A, 2
    STA 0xF000110F      ; грань +X, треугольник 2

    LDI A, 4
    STA 0xF000110F      ; Gpu3D COMMAND = PRESENT

    ; ---- повернуть куб на пару градусов ----

    LDA 0xF0001119      ; OBJ_YAW_LOW
    LDI B, 2
    ADD B
    STA 0xF0001119
    LDA 0xF000111A      ; OBJ_YAW_HIGH
    LDI B, 0
    ADC B
    STA 0xF000111A

    ; ---- пауза - 60 кадров/сек через Clock ----

    LDI A, 0
    STA 0xF0000FFC      ; Clock: сброс

delay_loop:
    LDA 0xF0000FFD      ; Clock MILLIS_HIGH
    LDI B, 0
    CMP B
    JNZ cube3d_loop

    LDA 0xF0000FFC      ; Clock MILLIS_LOW
    LDI B, 17           ; ~16.7 мс = 60 кадров/сек
    CMP B
    JC delay_loop

    JMP cube3d_loop


cube3d_exit:

    LDI A, 2
    STA 0xF0000FE9      ; VideoCard COMMAND = MODE_OFF

    DI

    RET


; ---- 8 вершин куба (±30 по каждой оси) ----

v0:
    LDI A, 226
    STA 0xF0001100      ; VX_LOW = -30
    LDI A, 255
    STA 0xF0001101
    LDI A, 226
    STA 0xF0001102      ; VY_LOW = -30
    LDI A, 255
    STA 0xF0001103
    LDI A, 226
    STA 0xF0001104      ; VZ_LOW = -30
    LDI A, 255
    STA 0xF0001105
    RET

v1:
    LDI A, 30
    STA 0xF0001100      ; VX_LOW = 30
    LDI A, 0
    STA 0xF0001101
    LDI A, 226
    STA 0xF0001102      ; VY_LOW = -30
    LDI A, 255
    STA 0xF0001103
    LDI A, 226
    STA 0xF0001104      ; VZ_LOW = -30
    LDI A, 255
    STA 0xF0001105
    RET

v2:
    LDI A, 30
    STA 0xF0001100      ; VX_LOW = 30
    LDI A, 0
    STA 0xF0001101
    LDI A, 30
    STA 0xF0001102      ; VY_LOW = 30
    LDI A, 0
    STA 0xF0001103
    LDI A, 226
    STA 0xF0001104      ; VZ_LOW = -30
    LDI A, 255
    STA 0xF0001105
    RET

v3:
    LDI A, 226
    STA 0xF0001100      ; VX_LOW = -30
    LDI A, 255
    STA 0xF0001101
    LDI A, 30
    STA 0xF0001102      ; VY_LOW = 30
    LDI A, 0
    STA 0xF0001103
    LDI A, 226
    STA 0xF0001104      ; VZ_LOW = -30
    LDI A, 255
    STA 0xF0001105
    RET

v4:
    LDI A, 226
    STA 0xF0001100      ; VX_LOW = -30
    LDI A, 255
    STA 0xF0001101
    LDI A, 226
    STA 0xF0001102      ; VY_LOW = -30
    LDI A, 255
    STA 0xF0001103
    LDI A, 30
    STA 0xF0001104      ; VZ_LOW = 30
    LDI A, 0
    STA 0xF0001105
    RET

v5:
    LDI A, 30
    STA 0xF0001100      ; VX_LOW = 30
    LDI A, 0
    STA 0xF0001101
    LDI A, 226
    STA 0xF0001102      ; VY_LOW = -30
    LDI A, 255
    STA 0xF0001103
    LDI A, 30
    STA 0xF0001104      ; VZ_LOW = 30
    LDI A, 0
    STA 0xF0001105
    RET

v6:
    LDI A, 30
    STA 0xF0001100      ; VX_LOW = 30
    LDI A, 0
    STA 0xF0001101
    LDI A, 30
    STA 0xF0001102      ; VY_LOW = 30
    LDI A, 0
    STA 0xF0001103
    LDI A, 30
    STA 0xF0001104      ; VZ_LOW = 30
    LDI A, 0
    STA 0xF0001105
    RET

v7:
    LDI A, 226
    STA 0xF0001100      ; VX_LOW = -30
    LDI A, 255
    STA 0xF0001101
    LDI A, 30
    STA 0xF0001102      ; VY_LOW = 30
    LDI A, 0
    STA 0xF0001103
    LDI A, 30
    STA 0xF0001104      ; VZ_LOW = 30
    LDI A, 0
    STA 0xF0001105
    RET


; ---- цвета граней ----

c_red:
    LDI A, 255
    STA 0xF0001106
    LDI A, 0
    STA 0xF0001107
    STA 0xF0001108
    RET

c_green:
    LDI A, 0
    STA 0xF0001106
    LDI A, 255
    STA 0xF0001107
    LDI A, 0
    STA 0xF0001108
    RET

c_blue:
    LDI A, 0
    STA 0xF0001106
    STA 0xF0001107
    LDI A, 255
    STA 0xF0001108
    RET

c_yellow:
    LDI A, 255
    STA 0xF0001106
    STA 0xF0001107
    LDI A, 0
    STA 0xF0001108
    RET

c_magenta:
    LDI A, 255
    STA 0xF0001106
    LDI A, 0
    STA 0xF0001107
    LDI A, 255
    STA 0xF0001108
    RET

c_cyan:
    LDI A, 0
    STA 0xF0001106
    LDI A, 255
    STA 0xF0001107
    STA 0xF0001108
    RET
