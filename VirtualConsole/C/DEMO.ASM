; ============================================================
; DEMO.ASM - демо для видеокарты (VideoCard): прыгающий цветной
; квадрат ("DVD-заставка"). Запускается из шелла командой
; "exec demo.asm" - Disk.LOAD собирает и вызывает этот файл как
; обычную подпрограмму (CALL 0x00002000, см. cmd_exec_run в
; SHELL.ASM), поэтому файл просто начинается с кода - вектор
; прерывания уже настроен резидентным SHELL.ASM, трогать его тут
; не нужно.
;
; Координаты видеокарты - 16 бит (0-319/0-239), а регистры A/B/C/D
; только 8-битные. Чтобы не городить полноценную 16-битную
; арифметику сравнения, позиция квадрата хранится в "юнитах" по
; 2 пикселя (0-150 по X, 0-110 по Y - оба влезают в 8 бит), а
; перевод в настоящие пиксели для регистров видеокарты делается
; раз за кадр через ADD A,A (A=A*2) - CARRY после такого удвоения
; и есть старший байт итогового 16-битного пикселя (см. ADD/ADC в
; ASSEMBLY.md про этот приём).
;
; ESC во время демо ведёт себя так же, как и во всей системе -
; завершает всю VM (см. SHELL.ASM/irq_handler). EI ниже специально
; нужен, чтобы клавиатурное прерывание вообще могло сработать во
; время цикла демо (dispatch_command вызывается с прерываниями
; выключенными - см. CPU::step про interruptsEnabled). Перед
; выходом закрываем окно видеокарты (MODE_OFF), чтобы не оставить
; висящий поток.
; ============================================================

    EI

    LDI A, 1
    STA 0xF0000FE9      ; VideoCard COMMAND = MODE_ON

    LDI A, 0
    STA 0xF0000FE6      ; R = 0
    STA 0xF0000FE7      ; G = 0
    STA 0xF0000FE8      ; B = 0
    LDI A, 3
    STA 0xF0000FE9      ; COMMAND = CLEAR (весь экран чёрным)

    LDI A, 20
    STA 0xF0000FE2      ; W_LOW = 20 - размер квадрата не меняется,
    LDI A, 0            ; выставляем один раз на весь запуск
    STA 0xF0000FE3      ; W_HIGH = 0
    LDI A, 20
    STA 0xF0000FE4      ; H_LOW = 20
    LDI A, 0
    STA 0xF0000FE5      ; H_HIGH = 0

    LDI A, 0
    STA posXUnit
    STA posYUnit
    LDI A, 1
    STA dirXPositive
    STA dirYPositive
    LDI A, 0
    STA colorIndex


demo_loop:

    LDA 0x00010001      ; lastKey - общий "интерфейсный" адрес,
                         ; тот же самый читает и обновляет SHELL
    LDI B, 27           ; ESC
    CMP B
    JZ demo_exit

    ; ---- стереть квадрат на старой позиции (чёрным) ----

    CALL set_xy_from_units

    LDI A, 0
    STA 0xF0000FE6
    STA 0xF0000FE7
    STA 0xF0000FE8
    LDI A, 5
    STA 0xF0000FE9      ; COMMAND = FILL_RECT

    ; ---- сдвинуть X ----

    LDA dirXPositive
    LDI B, 0
    CMP B
    JZ move_x_neg

move_x_pos:

    LDA posXUnit
    LDI B, 2
    ADD B
    STA posXUnit
    LDI B, 150          ; X_MAX_UNIT (150*2=300=320-20)
    CMP B
    JC move_x_done
    LDI A, 150
    STA posXUnit
    LDI A, 0
    STA dirXPositive
    CALL next_color
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
    CALL next_color

move_x_done:

    ; ---- сдвинуть Y (та же схема, что и X) ----

    LDA dirYPositive
    LDI B, 0
    CMP B
    JZ move_y_neg

move_y_pos:

    LDA posYUnit
    LDI B, 2
    ADD B
    STA posYUnit
    LDI B, 110          ; Y_MAX_UNIT (110*2=220=240-20)
    CMP B
    JC move_y_done
    LDI A, 110
    STA posYUnit
    LDI A, 0
    STA dirYPositive
    CALL next_color
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
    CALL next_color

move_y_done:

    ; ---- нарисовать квадрат на новой позиции текущим цветом ----

    CALL set_xy_from_units
    CALL set_color_from_index

    LDI A, 5
    STA 0xF0000FE9      ; COMMAND = FILL_RECT

    ; ---- пауза между кадрами - реальное время, не такты шины ----
    ; Clock (см. ASSEMBLY.md) отдаёт настоящие миллисекунды по
    ; std::chrono, независимо от скорости хоста - в отличие от Timer,
    ; чей counter растёт на каждое обращение к шине. 60 кадров/сек =
    ; ~16.7 мс между кадрами, порог 17 округляет чуть вверх.

    LDI A, 0
    STA 0xF0000FF8      ; Clock: запись в MILLIS_LOW сбрасывает часы

delay_loop:

    LDA 0xF0000FF9      ; Clock: MILLIS_HIGH
    LDI B, 0
    CMP B
    JNZ demo_loop       ; прошло >=256 мс - явно достаточно, страховка
                         ; на случай зависания хоста между опросами

    LDA 0xF0000FF8      ; Clock: MILLIS_LOW
    LDI B, 17           ; ~16.7 мс = 60 кадров/сек
    CMP B
    JC delay_loop

    JMP demo_loop


demo_exit:

    LDI A, 2
    STA 0xF0000FE9      ; VideoCard COMMAND = MODE_OFF

    DI                  ; восстанавливаем инвариант "прерывания
                         ; выключены во время dispatch_command",
                         ; который держит весь остальной SHELL

    RET


set_xy_from_units:

    ; X_LOW/X_HIGH/Y_LOW/Y_HIGH = posXUnit*2 / posYUnit*2 (16 бит) -
    ; см. комментарий в шапке файла про приём ADD A,A + CARRY.

    LDA posXUnit
    PUSH A
    POP B
    ADD B
    STA 0xF0000FDE      ; X_LOW
    JNC sxy_xhigh0
    LDI A, 1
    JMP sxy_xhigh_done
sxy_xhigh0:
    LDI A, 0
sxy_xhigh_done:
    STA 0xF0000FDF      ; X_HIGH

    LDA posYUnit
    PUSH A
    POP B
    ADD B
    STA 0xF0000FE0      ; Y_LOW
    JNC sxy_yhigh0
    LDI A, 1
    JMP sxy_yhigh_done
sxy_yhigh0:
    LDI A, 0
sxy_yhigh_done:
    STA 0xF0000FE1      ; Y_HIGH

    RET


set_color_from_index:

    LDA colorIndex
    LDI B, 0
    CMP B
    JZ sc_red
    LDI B, 1
    CMP B
    JZ sc_green
    LDI B, 2
    CMP B
    JZ sc_blue
    JMP sc_yellow

sc_red:
    LDI A, 255
    STA 0xF0000FE6
    LDI A, 0
    STA 0xF0000FE7
    STA 0xF0000FE8
    RET

sc_green:
    LDI A, 0
    STA 0xF0000FE6
    LDI A, 255
    STA 0xF0000FE7
    LDI A, 0
    STA 0xF0000FE8
    RET

sc_blue:
    LDI A, 0
    STA 0xF0000FE6
    STA 0xF0000FE7
    LDI A, 255
    STA 0xF0000FE8
    RET

sc_yellow:
    LDI A, 255
    STA 0xF0000FE6
    STA 0xF0000FE7
    LDI A, 0
    STA 0xF0000FE8
    RET


next_color:

    LDA colorIndex
    LDI B, 1
    ADD B
    LDI B, 4
    CMP B
    JNZ nc_store
    LDI A, 0

nc_store:
    STA colorIndex
    RET


posXUnit:      DB 0
posYUnit:      DB 0
dirXPositive:  DB 1
dirYPositive:  DB 1
colorIndex:    DB 0
