; ============================================================
; SPRITES.ASM - демо аппаратных спрайтов с PNG-спрайтшита.
; Запускается из шелла командой "exec sprites.asm".
;
; Грузит SPRITES.PNG (сетка 7x7 ячеек 32x32, см. PngLoader в
; ASSEMBLY.md) через PngLoader, раскладывает 15 персонажей
; неподвижным фоном (спрайты 0-14) и один - спрайт 15 - летает по
; экрану и отражается от краёв, как квадрат в DEMO.ASM, только тут
; НЕ нужно вручную стирать/рисовать его каждый кадр (FILL_RECT) -
; видеокарта сама убирает спрайт со старой позиции и рисует на новой
; при композиции кадра (см. VideoCard::compositeSprites) - в цикле
; ниже просто переставляются SPRITE_X/SPRITE_Y.
;
; ESC ведёт себя как везде в системе - завершает всю VM (см.
; SHELL.ASM/irq_handler). EI нужен, чтобы клавиатурное прерывание
; вообще могло сработать во время цикла (dispatch_command вызывается
; с прерываниями выключенными - см. CPU::step).
; ============================================================

    EI

    ; ---- загрузить спрайтшит ----

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

    LDA 0xF0001010      ; PngLoader STATUS
    LDI B, 0
    CMP B
    JNZ sprites_error   ; файл не найден/не декодировался - молча выходим

    LDI A, 1
    STA 0xF0000FE9      ; VideoCard COMMAND = MODE_ON

    ; ---- 15 неподвижных персонажей фоном (спрайты 0-14) ----
    ; Ячейки спрайтшита (SRC_X,SRC_Y) и позиции на экране (X,Y)
    ; подобраны так, чтобы не пересекаться - см. ASSEMBLY.md.

    CALL place_bg0
    CALL place_bg1
    CALL place_bg2
    CALL place_bg3
    CALL place_bg4
    CALL place_bg5
    CALL place_bg6
    CALL place_bg7
    CALL place_bg8
    CALL place_bg9
    CALL place_bg10
    CALL place_bg11
    CALL place_bg12
    CALL place_bg13
    CALL place_bg14

    ; ---- летающий персонаж - спрайт 15 ----

    LDI A, 192
    STA 0xF000100A      ; SRC_X_LOW
    LDI A, 0
    STA 0xF000100B
    LDI A, 64
    STA 0xF000100C      ; SRC_Y_LOW
    LDI A, 0
    STA 0xF000100D
    LDI A, 15
    STA 0xF000100E      ; PngLoader SPRITE_INDEX = 15
    LDI A, 2
    STA 0xF000100F      ; COMMAND = EXTRACT

    LDI A, 15
    STA 0xF0000FEB      ; VideoCard SPRITE_INDEX = 15 - и оставляем
                         ; так на весь цикл ниже, больше не меняем
    LDI A, 1
    STA 0xF0000FF2      ; SPRITE_VISIBLE = 1

    LDI A, 0
    STA posXUnit
    STA posYUnit
    LDI A, 1
    STA dirXPositive
    STA dirYPositive


sprites_loop:

    LDA 0x00010001      ; lastKey - тот же адрес читает и SHELL
    LDI B, 27           ; ESC
    CMP B
    JZ sprites_exit

    ; ---- сдвинуть X (юниты по 2px, как в DEMO.ASM) ----

    LDA dirXPositive
    LDI B, 0
    CMP B
    JZ move_x_neg

move_x_pos:

    LDA posXUnit
    LDI B, 2
    ADD B
    STA posXUnit
    LDI B, 144          ; X_MAX_UNIT (144*2=288=320-32)
    CMP B
    JC move_x_done
    LDI A, 144
    STA posXUnit
    LDI A, 0
    STA dirXPositive
    JMP move_x_done

move_x_neg:

    LDA posXUnit
    LDI B, 2
    CMP B
    JC move_x_clamp0
    SUB B
    STA posXUnit
    JMP move_x_done

move_x_clamp0:

    LDI A, 0
    STA posXUnit
    LDI A, 1
    STA dirXPositive

move_x_done:

    ; ---- сдвинуть Y (та же схема) ----

    LDA dirYPositive
    LDI B, 0
    CMP B
    JZ move_y_neg

move_y_pos:

    LDA posYUnit
    LDI B, 2
    ADD B
    STA posYUnit
    LDI B, 104          ; Y_MAX_UNIT (104*2=208=240-32)
    CMP B
    JC move_y_done
    LDI A, 104
    STA posYUnit
    LDI A, 0
    STA dirYPositive
    JMP move_y_done

move_y_neg:

    LDA posYUnit
    LDI B, 2
    CMP B
    JC move_y_clamp0
    SUB B
    STA posYUnit
    JMP move_y_done

move_y_clamp0:

    LDI A, 0
    STA posYUnit
    LDI A, 1
    STA dirYPositive

move_y_done:

    ; ---- применить позицию к спрайту 15 (ADD A,A + CARRY, см. DEMO.ASM) ----

    LDA posXUnit
    PUSH A
    POP B
    ADD B
    STA 0xF0000FEE      ; SPRITE_X_LOW
    JNC sp_xhigh0
    LDI A, 1
    JMP sp_xhigh_done
sp_xhigh0:
    LDI A, 0
sp_xhigh_done:
    STA 0xF0000FEF      ; SPRITE_X_HIGH

    LDA posYUnit
    PUSH A
    POP B
    ADD B
    STA 0xF0000FF0      ; SPRITE_Y_LOW
    JNC sp_yhigh0
    LDI A, 1
    JMP sp_yhigh_done
sp_yhigh0:
    LDI A, 0
sp_yhigh_done:
    STA 0xF0000FF1      ; SPRITE_Y_HIGH

    ; ---- пауза - 60 кадров/сек через Clock (см. DEMO.ASM) ----

    LDI A, 0
    STA 0xF0000FFC      ; Clock: сброс

delay_loop:

    LDA 0xF0000FFD      ; Clock MILLIS_HIGH
    LDI B, 0
    CMP B
    JNZ sprites_loop

    LDA 0xF0000FFC      ; Clock MILLIS_LOW
    LDI B, 17           ; ~16.7 мс = 60 кадров/сек
    CMP B
    JC delay_loop

    JMP sprites_loop


sprites_exit:

    LDI A, 2
    STA 0xF0000FE9      ; VideoCard COMMAND = MODE_OFF

sprites_error:

    DI                  ; восстанавливаем инвариант "прерывания
                         ; выключены во время dispatch_command"

    RET


; ---- размещение фоновых персонажей (спрайты 0-14) ----
; Каждый - EXTRACT из своей ячейки спрайтшита + позиция/видимость.

place_bg0:
    LDI A, 0
    STA 0xF000100A
    LDI A, 0
    STA 0xF000100B
    STA 0xF000100C
    STA 0xF000100D
    LDI A, 0
    STA 0xF000100E
    LDI A, 2
    STA 0xF000100F
    LDI A, 0
    STA 0xF0000FEB
    LDI A, 10
    STA 0xF0000FEE
    LDI A, 0
    STA 0xF0000FEF
    LDI A, 10
    STA 0xF0000FF0
    LDI A, 0
    STA 0xF0000FF1
    LDI A, 1
    STA 0xF0000FF2
    RET

place_bg1:
    LDI A, 32
    STA 0xF000100A
    LDI A, 0
    STA 0xF000100B
    STA 0xF000100C
    STA 0xF000100D
    LDI A, 1
    STA 0xF000100E
    LDI A, 2
    STA 0xF000100F
    LDI A, 1
    STA 0xF0000FEB
    LDI A, 72
    STA 0xF0000FEE
    LDI A, 0
    STA 0xF0000FEF
    LDI A, 10
    STA 0xF0000FF0
    LDI A, 0
    STA 0xF0000FF1
    LDI A, 1
    STA 0xF0000FF2
    RET

place_bg2:
    LDI A, 64
    STA 0xF000100A
    LDI A, 0
    STA 0xF000100B
    STA 0xF000100C
    STA 0xF000100D
    LDI A, 2
    STA 0xF000100E
    LDI A, 2
    STA 0xF000100F
    LDI A, 2
    STA 0xF0000FEB
    LDI A, 134
    STA 0xF0000FEE
    LDI A, 0
    STA 0xF0000FEF
    LDI A, 10
    STA 0xF0000FF0
    LDI A, 0
    STA 0xF0000FF1
    LDI A, 1
    STA 0xF0000FF2
    RET

place_bg3:
    LDI A, 96
    STA 0xF000100A
    LDI A, 0
    STA 0xF000100B
    STA 0xF000100C
    STA 0xF000100D
    LDI A, 3
    STA 0xF000100E
    LDI A, 2
    STA 0xF000100F
    LDI A, 3
    STA 0xF0000FEB
    LDI A, 196
    STA 0xF0000FEE
    LDI A, 0
    STA 0xF0000FEF
    LDI A, 10
    STA 0xF0000FF0
    LDI A, 0
    STA 0xF0000FF1
    LDI A, 1
    STA 0xF0000FF2
    RET

place_bg4:
    LDI A, 128
    STA 0xF000100A
    LDI A, 0
    STA 0xF000100B
    STA 0xF000100C
    STA 0xF000100D
    LDI A, 4
    STA 0xF000100E
    LDI A, 2
    STA 0xF000100F
    LDI A, 4
    STA 0xF0000FEB
    LDI A, 2         ; X = 258 = 1*256+2
    STA 0xF0000FEE
    LDI A, 1
    STA 0xF0000FEF
    LDI A, 10
    STA 0xF0000FF0
    LDI A, 0
    STA 0xF0000FF1
    LDI A, 1
    STA 0xF0000FF2
    RET

place_bg5:
    LDI A, 0
    STA 0xF000100A
    LDI A, 0
    STA 0xF000100B
    LDI A, 32
    STA 0xF000100C
    LDI A, 0
    STA 0xF000100D
    LDI A, 5
    STA 0xF000100E
    LDI A, 2
    STA 0xF000100F
    LDI A, 5
    STA 0xF0000FEB
    LDI A, 10
    STA 0xF0000FEE
    LDI A, 0
    STA 0xF0000FEF
    LDI A, 72
    STA 0xF0000FF0
    LDI A, 0
    STA 0xF0000FF1
    LDI A, 1
    STA 0xF0000FF2
    RET

place_bg6:
    LDI A, 32
    STA 0xF000100A
    LDI A, 0
    STA 0xF000100B
    LDI A, 32
    STA 0xF000100C
    LDI A, 0
    STA 0xF000100D
    LDI A, 6
    STA 0xF000100E
    LDI A, 2
    STA 0xF000100F
    LDI A, 6
    STA 0xF0000FEB
    LDI A, 72
    STA 0xF0000FEE
    LDI A, 0
    STA 0xF0000FEF
    LDI A, 72
    STA 0xF0000FF0
    LDI A, 0
    STA 0xF0000FF1
    LDI A, 1
    STA 0xF0000FF2
    RET

place_bg7:
    LDI A, 64
    STA 0xF000100A
    LDI A, 0
    STA 0xF000100B
    LDI A, 32
    STA 0xF000100C
    LDI A, 0
    STA 0xF000100D
    LDI A, 7
    STA 0xF000100E
    LDI A, 2
    STA 0xF000100F
    LDI A, 7
    STA 0xF0000FEB
    LDI A, 134
    STA 0xF0000FEE
    LDI A, 0
    STA 0xF0000FEF
    LDI A, 72
    STA 0xF0000FF0
    LDI A, 0
    STA 0xF0000FF1
    LDI A, 1
    STA 0xF0000FF2
    RET

place_bg8:
    LDI A, 96
    STA 0xF000100A
    LDI A, 0
    STA 0xF000100B
    LDI A, 32
    STA 0xF000100C
    LDI A, 0
    STA 0xF000100D
    LDI A, 8
    STA 0xF000100E
    LDI A, 2
    STA 0xF000100F
    LDI A, 8
    STA 0xF0000FEB
    LDI A, 196
    STA 0xF0000FEE
    LDI A, 0
    STA 0xF0000FEF
    LDI A, 72
    STA 0xF0000FF0
    LDI A, 0
    STA 0xF0000FF1
    LDI A, 1
    STA 0xF0000FF2
    RET

place_bg9:
    LDI A, 128
    STA 0xF000100A
    LDI A, 0
    STA 0xF000100B
    LDI A, 32
    STA 0xF000100C
    LDI A, 0
    STA 0xF000100D
    LDI A, 9
    STA 0xF000100E
    LDI A, 2
    STA 0xF000100F
    LDI A, 9
    STA 0xF0000FEB
    LDI A, 2         ; X = 258 = 1*256+2
    STA 0xF0000FEE
    LDI A, 1
    STA 0xF0000FEF
    LDI A, 72
    STA 0xF0000FF0
    LDI A, 0
    STA 0xF0000FF1
    LDI A, 1
    STA 0xF0000FF2
    RET

place_bg10:
    LDI A, 0
    STA 0xF000100A
    LDI A, 0
    STA 0xF000100B
    LDI A, 64
    STA 0xF000100C
    LDI A, 0
    STA 0xF000100D
    LDI A, 10
    STA 0xF000100E
    LDI A, 2
    STA 0xF000100F
    LDI A, 10
    STA 0xF0000FEB
    LDI A, 10
    STA 0xF0000FEE
    LDI A, 0
    STA 0xF0000FEF
    LDI A, 134
    STA 0xF0000FF0
    LDI A, 0
    STA 0xF0000FF1
    LDI A, 1
    STA 0xF0000FF2
    RET

place_bg11:
    LDI A, 32
    STA 0xF000100A
    LDI A, 0
    STA 0xF000100B
    LDI A, 64
    STA 0xF000100C
    LDI A, 0
    STA 0xF000100D
    LDI A, 11
    STA 0xF000100E
    LDI A, 2
    STA 0xF000100F
    LDI A, 11
    STA 0xF0000FEB
    LDI A, 72
    STA 0xF0000FEE
    LDI A, 0
    STA 0xF0000FEF
    LDI A, 134
    STA 0xF0000FF0
    LDI A, 0
    STA 0xF0000FF1
    LDI A, 1
    STA 0xF0000FF2
    RET

place_bg12:
    LDI A, 64
    STA 0xF000100A
    LDI A, 0
    STA 0xF000100B
    LDI A, 64
    STA 0xF000100C
    LDI A, 0
    STA 0xF000100D
    LDI A, 12
    STA 0xF000100E
    LDI A, 2
    STA 0xF000100F
    LDI A, 12
    STA 0xF0000FEB
    LDI A, 134
    STA 0xF0000FEE
    LDI A, 0
    STA 0xF0000FEF
    LDI A, 134
    STA 0xF0000FF0
    LDI A, 0
    STA 0xF0000FF1
    LDI A, 1
    STA 0xF0000FF2
    RET

place_bg13:
    LDI A, 96
    STA 0xF000100A
    LDI A, 0
    STA 0xF000100B
    LDI A, 64
    STA 0xF000100C
    LDI A, 0
    STA 0xF000100D
    LDI A, 13
    STA 0xF000100E
    LDI A, 2
    STA 0xF000100F
    LDI A, 13
    STA 0xF0000FEB
    LDI A, 196
    STA 0xF0000FEE
    LDI A, 0
    STA 0xF0000FEF
    LDI A, 134
    STA 0xF0000FF0
    LDI A, 0
    STA 0xF0000FF1
    LDI A, 1
    STA 0xF0000FF2
    RET

place_bg14:
    LDI A, 128
    STA 0xF000100A
    LDI A, 0
    STA 0xF000100B
    LDI A, 64
    STA 0xF000100C
    LDI A, 0
    STA 0xF000100D
    LDI A, 14
    STA 0xF000100E
    LDI A, 2
    STA 0xF000100F
    LDI A, 14
    STA 0xF0000FEB
    LDI A, 2         ; X = 258 = 1*256+2
    STA 0xF0000FEE
    LDI A, 1
    STA 0xF0000FEF
    LDI A, 134
    STA 0xF0000FF0
    LDI A, 0
    STA 0xF0000FF1
    LDI A, 1
    STA 0xF0000FF2
    RET


posXUnit:      DB 0
posYUnit:      DB 0
dirXPositive:  DB 1
dirYPositive:  DB 1
