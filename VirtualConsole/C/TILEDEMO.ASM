; ============================================================
; TILEDEMO.ASM - демо аппаратных тайлов со скроллингом.
; Запускается из шелла командой "exec tiledemo.asm".
;
; Грузит тайлсет TILES.PNG (8 тайлов 32x32 через PngLoader.EXTRACT_TILE)
; и карту MAP.TXT (40x30 тайлов = 1280x960 px, больше экрана 320x240 -
; через MapLoader), персонаж (SPRITES.PNG) стоит неподвижно в центре
; экрана, а карта под ним скроллит - "идёт по миру" случайным
; маршрутом: направление меняется и по таймеру, и при упирании в край
; карты (само устройство клэмпит SCROLL_X/Y, но клэмп без смены
; направления выглядел бы как "прилипание" к стенке - поэтому дошли до
; края сами проверяем и сразу выбираем новое направление).
;
; ESC ведёт себя как везде в системе - завершает всю VM. EI нужен для
; того же, для чего и в DEMO.ASM/SPRITES.ASM - без него клавиатурное
; прерывание не сработает во время цикла (dispatch_command вызывается
; с прерываниями выключенными - см. CPU::step).
; ============================================================

    EI

    ; ---- загрузить тайлсет ----

    LDI A, 84    ; T
    STA 0xF0000FFE
    LDI A, 73    ; I
    STA 0xF0000FFF
    LDI A, 76    ; L
    STA 0xF0001000
    LDI A, 69    ; E
    STA 0xF0001001
    LDI A, 83    ; S
    STA 0xF0001002
    LDI A, 46    ; .
    STA 0xF0001003
    LDI A, 80    ; P
    STA 0xF0001004
    LDI A, 78    ; N
    STA 0xF0001005
    LDI A, 71    ; G
    STA 0xF0001006
    LDI A, 0
    STA 0xF0001007
    STA 0xF0001008
    STA 0xF0001009

    LDI A, 1
    STA 0xF000100F      ; PngLoader COMMAND = LOAD

    LDA 0xF0001010       ; PngLoader STATUS
    LDI B, 0
    CMP B
    JNZ tiledemo_error

    ; ---- вырезать 8 тайлов (см. ASSEMBLY.md, "PngLoader") ----

    CALL extract_tile0
    CALL extract_tile1
    CALL extract_tile2
    CALL extract_tile3
    CALL extract_tile4
    CALL extract_tile5
    CALL extract_tile6
    CALL extract_tile7

    ; ---- загрузить карту ----

    LDI A, 77    ; M
    STA 0xF0001012
    LDI A, 65    ; A
    STA 0xF0001013
    LDI A, 80    ; P
    STA 0xF0001014
    LDI A, 46    ; .
    STA 0xF0001015
    LDI A, 84    ; T
    STA 0xF0001016
    LDI A, 88    ; X
    STA 0xF0001017
    LDI A, 84    ; T
    STA 0xF0001018
    LDI A, 0
    STA 0xF0001019
    STA 0xF000101A
    STA 0xF000101B
    STA 0xF000101C
    STA 0xF000101D

    LDI A, 1
    STA 0xF000101E      ; MapLoader COMMAND = LOAD

    LDA 0xF000101F       ; MapLoader STATUS
    LDI B, 0
    CMP B
    JNZ tiledemo_error

    ; ---- загрузить персонажа (спрайт 0), поставить в центр экрана ----

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

    LDA 0xF0001010
    LDI B, 0
    CMP B
    JNZ tiledemo_error

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
    LDI A, 144
    STA 0xF0000FEE      ; SPRITE_X_LOW = 144 = (320-32)/2
    LDI A, 0
    STA 0xF0000FEF
    LDI A, 104
    STA 0xF0000FF0      ; SPRITE_Y_LOW = 104 = (240-32)/2
    LDI A, 0
    STA 0xF0000FF1
    LDI A, 1
    STA 0xF0000FF2      ; SPRITE_VISIBLE = 1

    ; ---- открыть окно, начать со случайного направления ----

    LDI A, 1
    STA 0xF0000FE9      ; VideoCard COMMAND = MODE_ON

    LDI A, 0
    STA scrollXLow
    STA scrollXHigh
    STA scrollYLow
    STA scrollYHigh
    STA frameCount

    CALL pick_new_direction


tiledemo_loop:

    LDA 0x00010001      ; lastKey
    LDI B, 27           ; ESC
    CMP B
    JZ tiledemo_exit

    ; ---- раз в ~90 кадров (1.5 сек при 60fps) сменить направление ----

    LDA frameCount
    LDI B, 1
    ADD B
    STA frameCount
    LDI B, 90
    CMP B
    JNZ frame_count_done
    LDI A, 0
    STA frameCount
    CALL pick_new_direction

frame_count_done:

    ; ---- сдвинуть скролл по текущему направлению ----

    LDA dirCode
    LDI B, 0
    CMP B
    JZ move_up
    LDI B, 1
    CMP B
    JZ move_down
    LDI B, 2
    CMP B
    JZ move_left
    JMP move_right


move_up:

    LDA scrollYHigh
    LDI B, 0
    CMP B
    JNZ move_up_ok
    LDA scrollYLow
    LDI B, 0
    CMP B
    JZ move_edge

move_up_ok:
    LDA scrollYLow
    LDI B, 1
    SUB B
    STA scrollYLow
    LDI B, 0
    SBC B
    STA scrollYHigh
    JMP move_done

move_down:

    LDA scrollYHigh
    LDI B, 2           ; MAX_SCROLL_Y_HIGH (720 = 2*256+208)
    CMP B
    JC move_down_ok
    JNZ move_edge
    LDA scrollYLow
    LDI B, 208         ; MAX_SCROLL_Y_LOW
    CMP B
    JC move_down_ok
    JMP move_edge

move_down_ok:
    LDA scrollYLow
    LDI B, 1
    ADD B
    STA scrollYLow
    LDI B, 0
    ADC B
    STA scrollYHigh
    JMP move_done

move_left:

    LDA scrollXHigh
    LDI B, 0
    CMP B
    JNZ move_left_ok
    LDA scrollXLow
    LDI B, 0
    CMP B
    JZ move_edge

move_left_ok:
    LDA scrollXLow
    LDI B, 1
    SUB B
    STA scrollXLow
    LDI B, 0
    SBC B
    STA scrollXHigh
    JMP move_done

move_right:

    LDA scrollXHigh
    LDI B, 3           ; MAX_SCROLL_X_HIGH (960 = 3*256+192)
    CMP B
    JC move_right_ok
    JNZ move_edge
    LDA scrollXLow
    LDI B, 192         ; MAX_SCROLL_X_LOW
    CMP B
    JC move_right_ok
    JMP move_edge

move_right_ok:
    LDA scrollXLow
    LDI B, 1
    ADD B
    STA scrollXLow
    LDI B, 0
    ADC B
    STA scrollXHigh
    JMP move_done


move_edge:

    CALL pick_new_direction

move_done:

    ; ---- применить скролл к видеокарте ----

    LDA scrollXLow
    STA 0xF0000FF8      ; SCROLL_X_LOW
    LDA scrollXHigh
    STA 0xF0000FF9      ; SCROLL_X_HIGH
    LDA scrollYLow
    STA 0xF0000FFA      ; SCROLL_Y_LOW
    LDA scrollYHigh
    STA 0xF0000FFB      ; SCROLL_Y_HIGH

    ; ---- пауза - 60 кадров/сек через Clock ----

    LDI A, 0
    STA 0xF0000FFC      ; Clock: сброс

delay_loop:

    LDA 0xF0000FFD      ; Clock MILLIS_HIGH
    LDI B, 0
    CMP B
    JNZ tiledemo_loop

    LDA 0xF0000FFC      ; Clock MILLIS_LOW
    LDI B, 17           ; ~16.7 мс = 60 кадров/сек
    CMP B
    JC delay_loop

    JMP tiledemo_loop


tiledemo_exit:

    LDI A, 2
    STA 0xF0000FE9      ; VideoCard COMMAND = MODE_OFF

tiledemo_error:

    DI

    RET


pick_new_direction:

    ; Clock MILLIS_LOW в момент вызова - неплохой источник
    ; псевдослучайности (реальное время, не завязанное на то, сколько
    ; тактов шины ушло на код) - % 4 даёт направление 0-3.

    LDA 0xF0000FFC
    LDI B, 4
    MOD B
    STA dirCode
    RET


; ---- вырезание 8 тайлов тайлсета (см. ASSEMBLY.md, "PngLoader") ----
; Ячейки картинки подобраны по сетке TILES.PNG (17x26 ячеек 32x32) -
; полностью непрозрачные фоновые тайлы (не декоративные PNG-спрайты
; на прозрачном фоне, которых на этом листе большинство).

extract_tile0:
    LDI A, 0
    STA 0xF000100A      ; SRC_X_LOW = 0
    STA 0xF000100B
    STA 0xF000100C      ; SRC_Y_LOW = 0
    STA 0xF000100D
    STA 0xF0001011      ; TILE_INDEX = 0
    LDI A, 3
    STA 0xF000100F      ; COMMAND = EXTRACT_TILE
    RET

extract_tile1:
    LDI A, 0
    STA 0xF000100A      ; SRC_X_LOW = 0
    STA 0xF000100B
    LDI A, 64
    STA 0xF000100C      ; SRC_Y_LOW = 64
    LDI A, 0
    STA 0xF000100D
    LDI A, 1
    STA 0xF0001011      ; TILE_INDEX = 1
    LDI A, 3
    STA 0xF000100F
    RET

extract_tile2:
    LDI A, 32
    STA 0xF000100A      ; SRC_X_LOW = 32
    LDI A, 0
    STA 0xF000100B
    LDI A, 64
    STA 0xF000100C      ; SRC_Y_LOW = 64
    LDI A, 0
    STA 0xF000100D
    LDI A, 2
    STA 0xF0001011      ; TILE_INDEX = 2
    LDI A, 3
    STA 0xF000100F
    RET

extract_tile3:
    LDI A, 32
    STA 0xF000100A      ; SRC_X_LOW = 32
    LDI A, 0
    STA 0xF000100B
    LDI A, 192
    STA 0xF000100C      ; SRC_Y_LOW = 192
    LDI A, 0
    STA 0xF000100D
    LDI A, 3
    STA 0xF0001011      ; TILE_INDEX = 3
    LDI A, 3
    STA 0xF000100F
    RET

extract_tile4:
    LDI A, 32
    STA 0xF000100A      ; SRC_X_LOW = 32
    LDI A, 0
    STA 0xF000100B
    LDI A, 0
    STA 0xF000100C      ; SRC_Y_LOW = 256 (256=1*256+0)
    LDI A, 1
    STA 0xF000100D
    LDI A, 4
    STA 0xF0001011      ; TILE_INDEX = 4
    LDI A, 3
    STA 0xF000100F
    RET

extract_tile5:
    LDI A, 96
    STA 0xF000100A      ; SRC_X_LOW = 96
    LDI A, 0
    STA 0xF000100B
    LDI A, 96
    STA 0xF000100C      ; SRC_Y_LOW = 352 (352=1*256+96)
    LDI A, 1
    STA 0xF000100D
    LDI A, 5
    STA 0xF0001011      ; TILE_INDEX = 5
    LDI A, 3
    STA 0xF000100F
    RET

extract_tile6:
    LDI A, 0
    STA 0xF000100A      ; SRC_X_LOW = 0
    STA 0xF000100B
    LDI A, 128
    STA 0xF000100C      ; SRC_Y_LOW = 384 (384=1*256+128)
    LDI A, 1
    STA 0xF000100D
    LDI A, 6
    STA 0xF0001011      ; TILE_INDEX = 6
    LDI A, 3
    STA 0xF000100F
    RET

extract_tile7:
    LDI A, 0
    STA 0xF000100A      ; SRC_X_LOW = 0
    STA 0xF000100B
    LDI A, 160
    STA 0xF000100C      ; SRC_Y_LOW = 416 (416=1*256+160)
    LDI A, 1
    STA 0xF000100D
    LDI A, 7
    STA 0xF0001011      ; TILE_INDEX = 7
    LDI A, 3
    STA 0xF000100F
    RET


scrollXLow:    DB 0
scrollXHigh:   DB 0
scrollYLow:    DB 0
scrollYHigh:   DB 0
dirCode:       DB 0
frameCount:    DB 0
