; ============================================================
; Стартовая программа VirtualConsole.
;
; Печатает баннер на экран (Text VRAM) и запускает интерактивный
; терминал: набранные символы отображаются на экране в реальном
; времени, Enter переводит строку, Backspace стирает символ.
; ESC завершает программу.
;
; Терминал также работает как простой командный shell: строка,
; набранная до Enter, сравнивается с одной из известных команд
; (help/cls/regs/dump/poke/run/reset) и выполняется - см.
; dispatch_command и обработчики cmd_* ниже.
; ============================================================

    JMP main
    JMP irq_handler

main:

    CALL draw_banner

    ; ---- Настройка клавиатуры ----

    LDI A, 1
    STA 0xF0000006      ; включить прерывания клавиатуры

    LDI A, 0
    STA 0x00010000      ; keyCount = 0
    STA quit            ; quit = 0
    STA cmdlen          ; cmdlen = 0

    LDI D, 0        ; D - константа "0" для сравнений на весь запуск

    LDI A, 62       ; '>'
    CALL print_char
    LDI A, 32       ; (пробел)
    CALL print_char

    LDI A, 1
    STA 0x00010002      ; bannerReady = 1 (баннер готов к отрисовке)

    EI

wait:

    LDA quit
    CMP D
    JZ wait

    DI

    ; ---- Демонстрация MUL/DIV/MOD: печатаем "Keys: " + keyCount ----
    ; (на последней строке экрана - она гарантированно не съедет
    ; прокруткой, т.к. терминал больше не пишет в VRAM)

    LDHL 0xF0000787     ; последняя строка (24), столбец 0
    LDI A, 0
    STA column
    LDI A, 24
    STA row

    LDI A, 75
    CALL print_char   ; K
    LDI A, 101
    CALL print_char   ; e
    LDI A, 121
    CALL print_char   ; y
    LDI A, 115
    CALL print_char   ; s
    LDI A, 58
    CALL print_char   ; :
    LDI A, 32
    CALL print_char   ; (пробел)

    LDA 0x00010000      ; keyCount
    CALL print_number

    LDI A, 1
    STA 0x00010003      ; doneReady = 1 (финальная надпись готова)

    HLT


irq_handler:

    PUSH A
    PUSH B
    PUSH C

    LDI A, 1
    STA 0xF0000006      ; подтвердить прерывание

    LDA 0xF0000005
    STA 0x00010001      ; lastKey = код клавиши

    LDA 0x00010001      ; A = код клавиши

    LDI B, 27       ; ESC
    CMP B
    JZ do_quit

    LDI B, 13       ; Enter
    CMP B
    JZ do_enter

    LDI B, 8        ; Backspace
    CMP B
    JZ do_backspace

    JMP do_echo


do_quit:

    LDI A, 1
    STA quit      ; quit = 1
    JMP irq_done


do_echo:

    STA lastChar    ; символ понадобится ниже для буфера команды,
                     ; а A будет занят под арифметику column/cmdlen

    STX             ; VRAM[HL] = A (код клавиши)
    INCHL

    LDA column
    LDI B, 1
    ADD B
    STA column      ; column++

    ; ---- дописываем символ в cmdbuf[cmdlen], если есть место (0-11) ----
    ; cmdbuf - не единый массив, а 12 отдельных переменных (cmdbuf0..11):
    ; так проще, чем городить сохранение/восстановление HL (который
    ; всё это время держит позицию курсора на экране, а сохранить его
    ; на стек нечем - PUSH работает только с 8-битными регистрами).

    LDA cmdlen
    LDI B, 0
    CMP B
    JNZ de_check1
    LDA lastChar
    STA cmdbuf0
    JMP de_buf_done

de_check1:
    LDA cmdlen
    LDI B, 1
    CMP B
    JNZ de_check2
    LDA lastChar
    STA cmdbuf1
    JMP de_buf_done

de_check2:
    LDA cmdlen
    LDI B, 2
    CMP B
    JNZ de_check3
    LDA lastChar
    STA cmdbuf2
    JMP de_buf_done

de_check3:
    LDA cmdlen
    LDI B, 3
    CMP B
    JNZ de_check4
    LDA lastChar
    STA cmdbuf3
    JMP de_buf_done

de_check4:
    LDA cmdlen
    LDI B, 4
    CMP B
    JNZ de_check5
    LDA lastChar
    STA cmdbuf4
    JMP de_buf_done

de_check5:
    LDA cmdlen
    LDI B, 5
    CMP B
    JNZ de_check6
    LDA lastChar
    STA cmdbuf5
    JMP de_buf_done

de_check6:
    LDA cmdlen
    LDI B, 6
    CMP B
    JNZ de_check7
    LDA lastChar
    STA cmdbuf6
    JMP de_buf_done

de_check7:
    LDA cmdlen
    LDI B, 7
    CMP B
    JNZ de_check8
    LDA lastChar
    STA cmdbuf7
    JMP de_buf_done

de_check8:
    LDA cmdlen
    LDI B, 8
    CMP B
    JNZ de_check9
    LDA lastChar
    STA cmdbuf8
    JMP de_buf_done

de_check9:
    LDA cmdlen
    LDI B, 9
    CMP B
    JNZ de_check10
    LDA lastChar
    STA cmdbuf9
    JMP de_buf_done

de_check10:
    LDA cmdlen
    LDI B, 10
    CMP B
    JNZ de_check11
    LDA lastChar
    STA cmdbuf10
    JMP de_buf_done

de_check11:
    LDA cmdlen
    LDI B, 11
    CMP B
    JNZ de_buf_done
    LDA lastChar
    STA cmdbuf11

de_buf_done:

    LDA cmdlen
    LDI B, 1
    ADD B
    STA cmdlen      ; cmdlen++ (может уйти выше 12 - просто перестаём
                     ; писать в буфер дальше, длина всё равно не
                     ; совпадёт ни с одной командой)

    ; ---- перенос строки на 80-м столбце (как раньше) ----

    LDA column
    LDI B, 80
    CMP B
    JNZ irq_done

    LDI A, 0
    STA column      ; column дошёл до 80 - перенос на новую строку

    CALL advance_row

    JMP irq_done


do_backspace:

    LDA column
    LDI B, 0
    CMP B
    JZ irq_done     ; column == 0 - стирать некуда, игнорируем

    DECHL

    LDI A, 32
    STX             ; затираем символ пробелом

    LDA column
    LDI B, 1
    SUB B
    STA column      ; column--

    LDA cmdlen
    LDI B, 1
    SUB B
    STA cmdlen      ; cmdlen-- (симметрично column)

    JMP irq_done


do_enter:

    ; savedA/B/C/D сюда НЕ трогаем: между нажатиями клавиш крутится
    ; wait-цикл ("LDA quit; CMP D; JZ wait"), который каждую итерацию
    ; затирает A - если бы do_enter захватывал "текущие" A/B/C/D на
    ; каждый Enter, "regs" после "run" всегда показывала бы нули
    ; вместо результата run (ровно так и было - нашли живым
    ; тестированием). Обновляет saved* только команда run.

    CALL print_newline
    CALL dispatch_command

    LDI A, 0
    STA cmdlen

    LDI A, 62       ; '>'
    CALL print_char
    LDI A, 32
    CALL print_char

    JMP irq_done


advance_row:

    LDA row
    LDI B, 1
    ADD B
    STA row         ; row++

    LDI B, 25
    CMP B
    JNZ advance_row_done

    ; row дошёл до 25 (за пределом экрана 0-24) - прокрутить и остаться
    ; на последней строке

    LDI A, 1
    STA 0xF00007D7      ; SCROLL (Text VRAM) - сдвинуть текст вверх
    STA 0xF0000FDC      ; SCROLL (TextAttr) - и цвет вместе с ним,
                         ; иначе после прокрутки цвет "отстанет" от текста

    LDHL 0xF0000787     ; последняя строка (24), столбец 0 (0xF0000007 + 24*80)

    LDI A, 24
    STA row

advance_row_done:

    RET


draw_banner:

    ; ---- Рамка 80x4 вокруг баннера, окрашенная отдельным цветом
    ; (голубой на чёрном) - показывает, что и псевдографика (CP866),
    ; и цвет (TextAttr) реально работают. Текст внутри - тот же, что
    ; был раньше, только на строках 1-2 вместо 0-1 (строка 0 и 3 -
    ; сама рамка). Терминал теперь начинается со строки 4 (было 2).

    ; ---- Строка 0: верхняя граница ----

    LDHL 0xF0000007
    LDI A, 0
    STA column
    STA row

    LDI A, 0xC9
    CALL print_char   ; ╔

    LDI A, 78
    STA tmp2
    LDI A, 0xCD
    CALL print_char_n ; ═ x78

    LDI A, 0xBB
    CALL print_char   ; ╗

    ; ---- Строка 1: "Virtual Console. ESC to quit." ----

    LDHL 0xF0000057     ; 0xF0000007 + 80
    LDI A, 0
    STA column
    LDI A, 1
    STA row

    LDI A, 0xBA
    CALL print_char   ; ║

    LDI A, 86
    CALL print_char   ; V
    LDI A, 105
    CALL print_char   ; i
    LDI A, 114
    CALL print_char   ; r
    LDI A, 116
    CALL print_char   ; t
    LDI A, 117
    CALL print_char   ; u
    LDI A, 97
    CALL print_char   ; a
    LDI A, 108
    CALL print_char   ; l
    LDI A, 32
    CALL print_char   ; (пробел)
    LDI A, 67
    CALL print_char   ; C
    LDI A, 111
    CALL print_char   ; o
    LDI A, 110
    CALL print_char   ; n
    LDI A, 115
    CALL print_char   ; s
    LDI A, 111
    CALL print_char   ; o
    LDI A, 108
    CALL print_char   ; l
    LDI A, 101
    CALL print_char   ; e
    LDI A, 46
    CALL print_char   ; .
    LDI A, 32
    CALL print_char   ; (пробел)
    LDI A, 69
    CALL print_char   ; E
    LDI A, 83
    CALL print_char   ; S
    LDI A, 67
    CALL print_char   ; C
    LDI A, 32
    CALL print_char   ; (пробел)
    LDI A, 116
    CALL print_char   ; t
    LDI A, 111
    CALL print_char   ; o
    LDI A, 32
    CALL print_char   ; (пробел)
    LDI A, 113
    CALL print_char   ; q
    LDI A, 117
    CALL print_char   ; u
    LDI A, 105
    CALL print_char   ; i
    LDI A, 116
    CALL print_char   ; t
    LDI A, 46
    CALL print_char   ; .

    ; 29 видимых символов - дополняем пробелами до 78
    LDI A, 49
    STA tmp2
    LDI A, 32
    CALL print_char_n

    LDI A, 0xBA
    CALL print_char   ; ║

    ; ---- Строка 2: объём доступной RAM ----

    LDHL 0xF00000A7     ; 0xF0000007 + 2*80
    LDI A, 0
    STA column
    LDI A, 2
    STA row

    LDI A, 0xBA
    CALL print_char   ; ║

    LDI A, 82
    CALL print_char   ; R
    LDI A, 65
    CALL print_char   ; A
    LDI A, 77
    CALL print_char   ; M
    LDI A, 58
    CALL print_char   ; :
    LDI A, 32
    CALL print_char   ; (пробел)
    LDI A, 52
    CALL print_char   ; 4
    LDI A, 32
    CALL print_char   ; (пробел)
    LDI A, 77
    CALL print_char   ; M
    LDI A, 66
    CALL print_char   ; B

    ; 9 видимых символов - дополняем пробелами до 78
    LDI A, 69
    STA tmp2
    LDI A, 32
    CALL print_char_n

    LDI A, 0xBA
    CALL print_char   ; ║

    ; ---- Строка 3: нижняя граница ----

    LDHL 0xF00000F7     ; 0xF0000007 + 3*80
    LDI A, 0
    STA column
    LDI A, 3
    STA row

    LDI A, 0xC8
    CALL print_char   ; ╚

    LDI A, 78
    STA tmp2
    LDI A, 0xCD
    CALL print_char_n ; ═ x78

    LDI A, 0xBC
    CALL print_char   ; ╝

    ; ---- Красим все 4 строки рамки в голубой (0x0E) на чёрном ----

    LDI A, 0
    STA row
    CALL goto_attr_row_start
    LDI A, 80
    STA tmp2
    LDI A, 0x0E
    CALL print_char_n

    LDI A, 1
    STA row
    CALL goto_attr_row_start
    LDI A, 80
    STA tmp2
    LDI A, 0x0E
    CALL print_char_n

    LDI A, 2
    STA row
    CALL goto_attr_row_start
    LDI A, 80
    STA tmp2
    LDI A, 0x0E
    CALL print_char_n

    LDI A, 3
    STA row
    CALL goto_attr_row_start
    LDI A, 80
    STA tmp2
    LDI A, 0x0E
    CALL print_char_n

    ; ---- Курсор терминала - строка 4 (сразу под рамкой) ----

    LDHL 0xF0000147     ; 0xF0000007 + 4*80
    LDI A, 0
    STA column
    LDI A, 4
    STA row

    RET


print_char:

    ; Печатает символ A в текущей позиции HL, увеличивает HL и
    ; column. Не обрабатывает перенос строки на 80-м столбце -
    ; это отдельно делает do_echo (там нужна ещё и логика cmdbuf).

    STX
    INCHL

    PUSH A
    PUSH B

    LDA column
    LDI B, 1
    ADD B
    STA column

    POP B
    POP A

    RET


print_newline:

    ; Переходит на следующую строку экрана - используется shell'ом
    ; (dispatch_command и обработчиками команд) вместо ручного набора
    ; текста через Enter.

    PUSH A
    PUSH B
    PUSH C

    LDA column
    PUSH A
    POP B           ; B = column

    LDI A, 80
    SUB B           ; A = 80 - column

    LDI C, 1

pnl_loop:

    INCHL
    SUB C
    CMP D
    JNZ pnl_loop

    LDI A, 0
    STA column

    CALL advance_row

    POP C
    POP B
    POP A

    RET


print_number:

    ; Печатает десятичное число (0-255) из A в текущей позиции HL.
    ; Цифры сначала выталкиваются в стек от младшей к старшей (с
    ; сентинелом 255 в основании), затем снимаются и печатаются -
    ; так получаем правильный порядок (старшая цифра первой).

    PUSH B
    PUSH D

    LDI B, 255
    PUSH B          ; сентинел конца цифр

pn_split:

    PUSH A
    POP D           ; D = копия текущего значения

    LDI B, 10
    MOD B           ; A = value % 10 (цифра)
    PUSH A          ; сохраняем цифру

    PUSH D
    POP A           ; восстанавливаем value

    LDI B, 10
    DIV B           ; A = value / 10 (частное)

    LDI B, 0
    CMP B
    JNZ pn_split    ; пока частное != 0

pn_print:

    POP A
    LDI B, 255
    CMP B
    JZ pn_done      ; дошли до сентинела

    LDI B, 48       ; '0'
    ADD B
    CALL print_char

    JMP pn_print

pn_done:

    POP D
    POP B
    RET


dispatch_command:

    ; Сравнивает cmdlen/cmdbuf0..11 с каждой известной командой по
    ; очереди: сначала длина (быстрый отсев), затем посимвольно.
    ; Если ничего не совпало - молча ничего не делаем.

    ; ---- help (4 символа) ----

    LDA cmdlen
    LDI B, 4
    CMP B
    JNZ check_cls

    LDA cmdbuf0
    LDI B, 104      ; 'h'
    CMP B
    JNZ check_cls
    LDA cmdbuf1
    LDI B, 101      ; 'e'
    CMP B
    JNZ check_cls
    LDA cmdbuf2
    LDI B, 108      ; 'l'
    CMP B
    JNZ check_cls
    LDA cmdbuf3
    LDI B, 112      ; 'p'
    CMP B
    JNZ check_cls

    CALL cmd_help
    JMP dispatch_done


check_cls:

    LDA cmdlen
    LDI B, 3
    CMP B
    JNZ check_regs

    LDA cmdbuf0
    LDI B, 99       ; 'c'
    CMP B
    JNZ check_regs
    LDA cmdbuf1
    LDI B, 108      ; 'l'
    CMP B
    JNZ check_regs
    LDA cmdbuf2
    LDI B, 115      ; 's'
    CMP B
    JNZ check_regs

    CALL cmd_cls
    JMP dispatch_done


check_regs:

    LDA cmdlen
    LDI B, 4
    CMP B
    JNZ check_dump

    LDA cmdbuf0
    LDI B, 114      ; 'r'
    CMP B
    JNZ check_dump
    LDA cmdbuf1
    LDI B, 101      ; 'e'
    CMP B
    JNZ check_dump
    LDA cmdbuf2
    LDI B, 103      ; 'g'
    CMP B
    JNZ check_dump
    LDA cmdbuf3
    LDI B, 115      ; 's'
    CMP B
    JNZ check_dump

    CALL cmd_regs
    JMP dispatch_done


check_dump:

    LDA cmdlen
    LDI B, 8
    CMP B
    JNZ check_poke

    LDA cmdbuf0
    LDI B, 100      ; 'd'
    CMP B
    JNZ check_poke
    LDA cmdbuf1
    LDI B, 117      ; 'u'
    CMP B
    JNZ check_poke
    LDA cmdbuf2
    LDI B, 109      ; 'm'
    CMP B
    JNZ check_poke
    LDA cmdbuf3
    LDI B, 112      ; 'p'
    CMP B
    JNZ check_poke
    LDA cmdbuf4
    LDI B, 32       ; (пробел)
    CMP B
    JNZ check_poke

    CALL cmd_dump
    JMP dispatch_done


check_poke:

    LDA cmdlen
    LDI B, 12
    CMP B
    JNZ check_run

    LDA cmdbuf0
    LDI B, 112      ; 'p'
    CMP B
    JNZ check_run
    LDA cmdbuf1
    LDI B, 111      ; 'o'
    CMP B
    JNZ check_run
    LDA cmdbuf2
    LDI B, 107      ; 'k'
    CMP B
    JNZ check_run
    LDA cmdbuf3
    LDI B, 101      ; 'e'
    CMP B
    JNZ check_run
    LDA cmdbuf4
    LDI B, 32       ; (пробел)
    CMP B
    JNZ check_run
    LDA cmdbuf8
    LDI B, 32       ; (пробел между адресом и значением)
    CMP B
    JNZ check_run

    CALL cmd_poke
    JMP dispatch_done


check_run:

    LDA cmdlen
    LDI B, 3
    CMP B
    JNZ check_reset

    LDA cmdbuf0
    LDI B, 114      ; 'r'
    CMP B
    JNZ check_reset
    LDA cmdbuf1
    LDI B, 117      ; 'u'
    CMP B
    JNZ check_reset
    LDA cmdbuf2
    LDI B, 110      ; 'n'
    CMP B
    JNZ check_reset

    CALL cmd_run
    JMP dispatch_done


check_reset:

    LDA cmdlen
    LDI B, 5
    CMP B
    JNZ check_dir

    LDA cmdbuf0
    LDI B, 114      ; 'r'
    CMP B
    JNZ check_dir
    LDA cmdbuf1
    LDI B, 101      ; 'e'
    CMP B
    JNZ check_dir
    LDA cmdbuf2
    LDI B, 115      ; 's'
    CMP B
    JNZ check_dir
    LDA cmdbuf3
    LDI B, 101      ; 'e'
    CMP B
    JNZ check_dir
    LDA cmdbuf4
    LDI B, 116      ; 't'
    CMP B
    JNZ check_dir

    CALL cmd_reset
    JMP dispatch_done


check_dir:

    ; "dir" (3 символа) - список файлов на диске C

    LDA cmdlen
    LDI B, 3
    CMP B
    JNZ check_type

    LDA cmdbuf0
    LDI B, 100      ; 'd'
    CMP B
    JNZ check_type
    LDA cmdbuf1
    LDI B, 105      ; 'i'
    CMP B
    JNZ check_type
    LDA cmdbuf2
    LDI B, 114      ; 'r'
    CMP B
    JNZ check_type

    CALL cmd_dir
    JMP dispatch_done


check_type:

    ; "type " + ровно 7 символов имени файла (см. help) = 12 символов,
    ; как у "poke NNN VVV" - фиксированная длина, т.к. без флага CARRY
    ; нет способа проверить "длина >= N", только точное равенство.

    LDA cmdlen
    LDI B, 12
    CMP B
    JNZ check_cd

    LDA cmdbuf0
    LDI B, 116      ; 't'
    CMP B
    JNZ check_cd
    LDA cmdbuf1
    LDI B, 121      ; 'y'
    CMP B
    JNZ check_cd
    LDA cmdbuf2
    LDI B, 112      ; 'p'
    CMP B
    JNZ check_cd
    LDA cmdbuf3
    LDI B, 101      ; 'e'
    CMP B
    JNZ check_cd
    LDA cmdbuf4
    LDI B, 32       ; (пробел)
    CMP B
    JNZ check_cd

    CALL cmd_type
    JMP dispatch_done


check_cd:

    ; "cd c" / "cd d" (4 символа)

    LDA cmdlen
    LDI B, 4
    CMP B
    JNZ check_exec

    LDA cmdbuf0
    LDI B, 99       ; 'c'
    CMP B
    JNZ check_exec
    LDA cmdbuf1
    LDI B, 100      ; 'd'
    CMP B
    JNZ check_exec
    LDA cmdbuf2
    LDI B, 32       ; (пробел)
    CMP B
    JNZ check_exec

    CALL cmd_cd
    JMP dispatch_done


check_exec:

    ; "exec " + ровно 7 символов имени файла (та же схема, что у
    ; "type" - фиксированная длина, без переменного аргумента)

    LDA cmdlen
    LDI B, 12
    CMP B
    JNZ dispatch_done

    LDA cmdbuf0
    LDI B, 101      ; 'e'
    CMP B
    JNZ dispatch_done
    LDA cmdbuf1
    LDI B, 120      ; 'x'
    CMP B
    JNZ dispatch_done
    LDA cmdbuf2
    LDI B, 101      ; 'e'
    CMP B
    JNZ dispatch_done
    LDA cmdbuf3
    LDI B, 99       ; 'c'
    CMP B
    JNZ dispatch_done
    LDA cmdbuf4
    LDI B, 32       ; (пробел)
    CMP B
    JNZ dispatch_done

    CALL cmd_exec

dispatch_done:

    RET


cmd_help:

    LDI A, 104
    CALL print_char   ; h
    LDI A, 101
    CALL print_char   ; e
    LDI A, 108
    CALL print_char   ; l
    LDI A, 112
    CALL print_char   ; p
    LDI A, 32
    CALL print_char
    LDI A, 99
    CALL print_char   ; c
    LDI A, 108
    CALL print_char   ; l
    LDI A, 115
    CALL print_char   ; s
    LDI A, 32
    CALL print_char
    LDI A, 114
    CALL print_char   ; r
    LDI A, 101
    CALL print_char   ; e
    LDI A, 103
    CALL print_char   ; g
    LDI A, 115
    CALL print_char   ; s

    CALL print_newline

    LDI A, 100
    CALL print_char   ; d
    LDI A, 117
    CALL print_char   ; u
    LDI A, 109
    CALL print_char   ; m
    LDI A, 112
    CALL print_char   ; p
    LDI A, 32
    CALL print_char
    LDI A, 112
    CALL print_char   ; p
    LDI A, 111
    CALL print_char   ; o
    LDI A, 107
    CALL print_char   ; k
    LDI A, 101
    CALL print_char   ; e

    CALL print_newline

    LDI A, 114
    CALL print_char   ; r
    LDI A, 117
    CALL print_char   ; u
    LDI A, 110
    CALL print_char   ; n
    LDI A, 32
    CALL print_char
    LDI A, 114
    CALL print_char   ; r
    LDI A, 101
    CALL print_char   ; e
    LDI A, 115
    CALL print_char   ; s
    LDI A, 101
    CALL print_char   ; e
    LDI A, 116
    CALL print_char   ; t

    CALL print_newline

    LDI A, 100
    CALL print_char   ; d
    LDI A, 105
    CALL print_char   ; i
    LDI A, 114
    CALL print_char   ; r
    LDI A, 32
    CALL print_char
    LDI A, 116
    CALL print_char   ; t
    LDI A, 121
    CALL print_char   ; y
    LDI A, 112
    CALL print_char   ; p
    LDI A, 101
    CALL print_char   ; e
    LDI A, 32
    CALL print_char
    LDI A, 78
    CALL print_char   ; N (имя - ровно 7 символов, дополнить пробелами)
    LDI A, 78
    CALL print_char   ; N
    LDI A, 78
    CALL print_char   ; N
    LDI A, 78
    CALL print_char   ; N
    LDI A, 78
    CALL print_char   ; N
    LDI A, 78
    CALL print_char   ; N
    LDI A, 78
    CALL print_char   ; N

    CALL print_newline

    LDI A, 99
    CALL print_char   ; c
    LDI A, 100
    CALL print_char   ; d
    LDI A, 32
    CALL print_char
    LDI A, 99
    CALL print_char   ; c
    LDI A, 47
    CALL print_char   ; /
    LDI A, 100
    CALL print_char   ; d

    CALL print_newline

    LDI A, 101
    CALL print_char   ; e
    LDI A, 120
    CALL print_char   ; x
    LDI A, 101
    CALL print_char   ; e
    LDI A, 99
    CALL print_char   ; c
    LDI A, 32
    CALL print_char
    LDI A, 78
    CALL print_char   ; N (имя - ровно 7 символов)
    LDI A, 78
    CALL print_char   ; N
    LDI A, 78
    CALL print_char   ; N
    LDI A, 78
    CALL print_char   ; N
    LDI A, 78
    CALL print_char   ; N
    LDI A, 78
    CALL print_char   ; N
    LDI A, 78
    CALL print_char   ; N

    CALL print_newline

    RET


cmd_cls:

    LDI A, 1
    STA 0xF00007D8    ; CLEAR (Text VRAM)
    STA 0xF0000FDD    ; CLEAR (TextAttr) - сбрасывает цвет к дефолту

    LDI A, 0
    STA column
    STA row

    LDHL 0xF0000007

    RET


cmd_regs:

    LDI A, 65    ; 'A'
    CALL print_char
    LDI A, 61    ; '='
    CALL print_char
    LDA savedA
    CALL print_number
    CALL print_newline

    LDI A, 66    ; 'B'
    CALL print_char
    LDI A, 61
    CALL print_char
    LDA savedB
    CALL print_number
    CALL print_newline

    LDI A, 67    ; 'C'
    CALL print_char
    LDI A, 61
    CALL print_char
    LDA savedC
    CALL print_number
    CALL print_newline

    LDI A, 68    ; 'D'
    CALL print_char
    LDI A, 61
    CALL print_char
    LDA savedD
    CALL print_number
    CALL print_newline

    LDI A, 80    ; 'P'
    CALL print_char
    LDI A, 67    ; 'C'
    CALL print_char
    LDI A, 61
    CALL print_char
    LDA 0xF00007D9
    CALL print_number
    LDI A, 46    ; '.'
    CALL print_char
    LDA 0xF00007DA
    CALL print_number
    LDI A, 46
    CALL print_char
    LDA 0xF00007DB
    CALL print_number
    LDI A, 46
    CALL print_char
    LDA 0xF00007DC
    CALL print_number
    CALL print_newline

    LDI A, 83    ; 'S'
    CALL print_char
    LDI A, 80    ; 'P'
    CALL print_char
    LDI A, 61
    CALL print_char
    LDA 0xF00007DD
    CALL print_number
    LDI A, 46
    CALL print_char
    LDA 0xF00007DE
    CALL print_number
    LDI A, 46
    CALL print_char
    LDA 0xF00007DF
    CALL print_number
    LDI A, 46
    CALL print_char
    LDA 0xF00007E0
    CALL print_number
    CALL print_newline

    LDI A, 72    ; 'H'
    CALL print_char
    LDI A, 76    ; 'L'
    CALL print_char
    LDI A, 61
    CALL print_char
    LDA 0xF00007E1
    CALL print_number
    LDI A, 46
    CALL print_char
    LDA 0xF00007E2
    CALL print_number
    LDI A, 46
    CALL print_char
    LDA 0xF00007E3
    CALL print_number
    LDI A, 46
    CALL print_char
    LDA 0xF00007E4
    CALL print_number
    CALL print_newline

    LDI A, 70    ; 'F'
    CALL print_char
    LDI A, 61
    CALL print_char
    LDA 0xF00007E5
    CALL print_number
    CALL print_newline

    RET


cmd_dump:

    ; --- разбор 3-значного (десятичного) адреса из cmdbuf5..7 ---

    LDA cmdbuf5
    LDI B, 48
    SUB B
    LDI B, 100
    MUL B
    STA tmp1              ; tmp1 = digit0 * 100

    LDA cmdbuf6
    LDI B, 48
    SUB B
    LDI B, 10
    MUL B                 ; A = digit1 * 10

    PUSH A
    POP C
    LDA tmp1
    ADD C
    STA tmp1              ; tmp1 += digit1*10

    LDA cmdbuf7
    LDI B, 48
    SUB B                 ; A = digit2

    PUSH A
    POP C
    LDA tmp1
    ADD C
    STA tmp1              ; tmp1 = адрес (0-255)

    ; --- читаем байт по этому адресу (та же песочница, что и poke -
    ; чтобы poke/dump работали согласованной парой) ---

    LDHL 0x00002000
    LDA tmp1
    CALL hl_add_offset    ; HL = 0x00002000 + tmp1

    LDX
    STA tmp2              ; tmp2 = значение по адресу

    ; --- восстанавливаем экранный курсор (HL выше был занят под
    ; чтение памяти - PUSH HL не существует, поэтому пересчитываем
    ; его заново из row) и печатаем результат ---

    CALL goto_row_start

    LDA tmp2
    CALL print_number

    CALL print_newline

    RET


cmd_poke:

    ; --- адрес (cmdbuf5..7) -> tmp1 ---

    LDA cmdbuf5
    LDI B, 48
    SUB B
    LDI B, 100
    MUL B
    STA tmp1

    LDA cmdbuf6
    LDI B, 48
    SUB B
    LDI B, 10
    MUL B
    PUSH A
    POP C
    LDA tmp1
    ADD C
    STA tmp1

    LDA cmdbuf7
    LDI B, 48
    SUB B
    PUSH A
    POP C
    LDA tmp1
    ADD C
    STA tmp1              ; tmp1 = offset

    ; --- значение (cmdbuf9..11) -> tmp2 ---

    LDA cmdbuf9
    LDI B, 48
    SUB B
    LDI B, 100
    MUL B
    STA tmp2

    LDA cmdbuf10
    LDI B, 48
    SUB B
    LDI B, 10
    MUL B
    PUSH A
    POP C
    LDA tmp2
    ADD C
    STA tmp2

    LDA cmdbuf11
    LDI B, 48
    SUB B
    PUSH A
    POP C
    LDA tmp2
    ADD C
    STA tmp2              ; tmp2 = value

    ; --- пишем value по адресу sandbox(0x00002000) + offset ---

    LDHL 0x00002000
    LDA tmp1
    CALL hl_add_offset

    LDA tmp2
    STX

    CALL goto_row_start   ; ничего не печатали - просто восстанавливаем
                           ; курсор экрана, HL был занят под запись

    RET


cmd_run:

    PUSH D          ; на случай, если код в песочнице испортит "константу 0"

    CALL 0x00002000

    STA savedA
    PUSH B
    POP A
    STA savedB
    PUSH C
    POP A
    STA savedC
    PUSH D
    POP A
    STA savedD

    POP D           ; восстанавливаем константу 0

    CALL goto_row_start   ; код в песочнице мог сам сдвинуть HL

    RET


cmd_reset:

    LDI A, 1
    STA 0xF00007D8    ; CLEAR (Text VRAM)
    STA 0xF0000FDD    ; CLEAR (TextAttr)

    CALL draw_banner  ; сама выставит column/row/HL и перекрасит рамку

    RET


cmd_dir:

    ; Печатаем, какой диск смотрим ("C:"/"D:"), затем список файлов.
    ; DiskC и DiskD - независимые устройства на разных фиксированных
    ; MMIO-адресах (не общий регистр выбора), поэтому тело команды
    ; продублировано под каждый диск (cmd_dir_c/cmd_dir_d) -
    ; переключаться HL между "указатель на регистр диска" и "курсор
    ; экрана" на каждый байт было бы тем же классом проблем, что и с
    ; dump/poke/run (нет PUSH HL, см. goto_row_start).

    LDA currentDisk
    CMP D
    JNZ cmd_dir_prefix_d

    LDI A, 67    ; 'C'
    CALL print_char
    LDI A, 58    ; ':'
    CALL print_char
    CALL print_newline
    JMP cmd_dir_c

cmd_dir_prefix_d:

    LDI A, 68    ; 'D'
    CALL print_char
    LDI A, 58    ; ':'
    CALL print_char
    CALL print_newline
    JMP cmd_dir_d


cmd_dir_c:

    ; NAME0..11 = 0xF00007E6..0xF00007F1, COMMAND = 0xF00007F2,
    ; STATUS = 0xF00007F3 (диск C, см. ASSEMBLY.md "Disk").

    LDI A, 1
    STA 0xF00007F2

cmd_dir_c_loop:

    LDA 0xF00007F3
    LDI B, 1
    CMP B
    JZ cmd_dir_c_done

    LDI B, 0

    LDA 0xF00007E6
    CMP B
    JZ cmd_dir_c_after_name
    CALL print_char
    LDA 0xF00007E7
    CMP B
    JZ cmd_dir_c_after_name
    CALL print_char
    LDA 0xF00007E8
    CMP B
    JZ cmd_dir_c_after_name
    CALL print_char
    LDA 0xF00007E9
    CMP B
    JZ cmd_dir_c_after_name
    CALL print_char
    LDA 0xF00007EA
    CMP B
    JZ cmd_dir_c_after_name
    CALL print_char
    LDA 0xF00007EB
    CMP B
    JZ cmd_dir_c_after_name
    CALL print_char
    LDA 0xF00007EC
    CMP B
    JZ cmd_dir_c_after_name
    CALL print_char
    LDA 0xF00007ED
    CMP B
    JZ cmd_dir_c_after_name
    CALL print_char
    LDA 0xF00007EE
    CMP B
    JZ cmd_dir_c_after_name
    CALL print_char
    LDA 0xF00007EF
    CMP B
    JZ cmd_dir_c_after_name
    CALL print_char
    LDA 0xF00007F0
    CMP B
    JZ cmd_dir_c_after_name
    CALL print_char
    LDA 0xF00007F1
    CMP B
    JZ cmd_dir_c_after_name
    CALL print_char

cmd_dir_c_after_name:

    CALL print_newline

    LDI A, 2
    STA 0xF00007F2
    JMP cmd_dir_c_loop

cmd_dir_c_done:

    RET


cmd_dir_d:

    ; NAME0..11 = 0xF00007F9..0xF0000804, COMMAND = 0xF0000805,
    ; STATUS = 0xF0000806 (диск D, см. ASSEMBLY.md "Disk").

    LDI A, 1
    STA 0xF0000805

cmd_dir_d_loop:

    LDA 0xF0000806
    LDI B, 1
    CMP B
    JZ cmd_dir_d_done

    LDI B, 0

    LDA 0xF00007F9
    CMP B
    JZ cmd_dir_d_after_name
    CALL print_char
    LDA 0xF00007FA
    CMP B
    JZ cmd_dir_d_after_name
    CALL print_char
    LDA 0xF00007FB
    CMP B
    JZ cmd_dir_d_after_name
    CALL print_char
    LDA 0xF00007FC
    CMP B
    JZ cmd_dir_d_after_name
    CALL print_char
    LDA 0xF00007FD
    CMP B
    JZ cmd_dir_d_after_name
    CALL print_char
    LDA 0xF00007FE
    CMP B
    JZ cmd_dir_d_after_name
    CALL print_char
    LDA 0xF00007FF
    CMP B
    JZ cmd_dir_d_after_name
    CALL print_char
    LDA 0xF0000800
    CMP B
    JZ cmd_dir_d_after_name
    CALL print_char
    LDA 0xF0000801
    CMP B
    JZ cmd_dir_d_after_name
    CALL print_char
    LDA 0xF0000802
    CMP B
    JZ cmd_dir_d_after_name
    CALL print_char
    LDA 0xF0000803
    CMP B
    JZ cmd_dir_d_after_name
    CALL print_char
    LDA 0xF0000804
    CMP B
    JZ cmd_dir_d_after_name
    CALL print_char

cmd_dir_d_after_name:

    CALL print_newline

    LDI A, 2
    STA 0xF0000805
    JMP cmd_dir_d_loop

cmd_dir_d_done:

    RET


cmd_type:

    LDA currentDisk
    CMP D
    JNZ cmd_type_d
    JMP cmd_type_c


cmd_type_c:

    ; "type ИМЯ" - ИМЯ должно быть ровно 7 символов (см. check_type/
    ; help): cmdbuf5..cmdbuf11 -> DiskC NAME0..6, NAME7..11 обнуляем,
    ; чтобы не осталось "хвоста" от предыдущего имени.

    LDA cmdbuf5
    STA 0xF00007E6
    LDA cmdbuf6
    STA 0xF00007E7
    LDA cmdbuf7
    STA 0xF00007E8
    LDA cmdbuf8
    STA 0xF00007E9
    LDA cmdbuf9
    STA 0xF00007EA
    LDA cmdbuf10
    STA 0xF00007EB
    LDA cmdbuf11
    STA 0xF00007EC

    LDI A, 0
    STA 0xF00007ED
    STA 0xF00007EE
    STA 0xF00007EF
    STA 0xF00007F0
    STA 0xF00007F1

    LDI A, 3
    STA 0xF00007F2

    LDA 0xF00007F3
    LDI B, 2
    CMP B
    JZ cmd_type_c_done

cmd_type_c_loop:

    LDI A, 4
    STA 0xF00007F2

    LDA 0xF00007F3
    LDI B, 1
    CMP B
    JZ cmd_type_c_close

    LDA 0xF00007F4

    LDI B, 10
    CMP B
    JNZ cmd_type_c_check_cr
    CALL print_newline
    JMP cmd_type_c_loop

cmd_type_c_check_cr:

    LDI B, 13
    CMP B
    JZ cmd_type_c_loop

    CALL print_char
    JMP cmd_type_c_loop

cmd_type_c_close:

    LDI A, 7
    STA 0xF00007F2

cmd_type_c_done:

    CALL print_newline

    RET


cmd_type_d:

    ; То же самое, но диск D: NAME0..6 = 0xF00007F9..0xF00007FF,
    ; NAME7..11 = 0xF0000800..0xF0000804, COMMAND = 0xF0000805,
    ; STATUS = 0xF0000806, DATA = 0xF0000807.

    LDA cmdbuf5
    STA 0xF00007F9
    LDA cmdbuf6
    STA 0xF00007FA
    LDA cmdbuf7
    STA 0xF00007FB
    LDA cmdbuf8
    STA 0xF00007FC
    LDA cmdbuf9
    STA 0xF00007FD
    LDA cmdbuf10
    STA 0xF00007FE
    LDA cmdbuf11
    STA 0xF00007FF

    LDI A, 0
    STA 0xF0000800
    STA 0xF0000801
    STA 0xF0000802
    STA 0xF0000803
    STA 0xF0000804

    LDI A, 3
    STA 0xF0000805

    LDA 0xF0000806
    LDI B, 2
    CMP B
    JZ cmd_type_d_done

cmd_type_d_loop:

    LDI A, 4
    STA 0xF0000805

    LDA 0xF0000806
    LDI B, 1
    CMP B
    JZ cmd_type_d_close

    LDA 0xF0000807

    LDI B, 10
    CMP B
    JNZ cmd_type_d_check_cr
    CALL print_newline
    JMP cmd_type_d_loop

cmd_type_d_check_cr:

    LDI B, 13
    CMP B
    JZ cmd_type_d_loop

    CALL print_char
    JMP cmd_type_d_loop

cmd_type_d_close:

    LDI A, 7
    STA 0xF0000805

cmd_type_d_done:

    CALL print_newline

    RET


cmd_cd:

    ; "cd c" / "cd d" (4 символа) - переключает currentDisk для
    ; dir/type. Символ диска - cmdbuf3.

    LDA cmdbuf3
    LDI B, 100    ; 'd'
    CMP B
    JNZ cmd_cd_c

    LDI A, 1
    STA currentDisk
    RET

cmd_cd_c:

    LDI A, 0
    STA currentDisk
    RET


cmd_exec:

    ; "exec ИМЯ" - собирает .asm-файл с текущего диска (currentDisk)
    ; и запускает его (LOAD в Disk - см. ASSEMBLY.md, "Disk"). ИМЯ -
    ; ровно 7 символов, как у "type".

    LDA currentDisk
    CMP D
    JNZ cmd_exec_d
    JMP cmd_exec_c


cmd_exec_c:

    LDA cmdbuf5
    STA 0xF00007E6
    LDA cmdbuf6
    STA 0xF00007E7
    LDA cmdbuf7
    STA 0xF00007E8
    LDA cmdbuf8
    STA 0xF00007E9
    LDA cmdbuf9
    STA 0xF00007EA
    LDA cmdbuf10
    STA 0xF00007EB
    LDA cmdbuf11
    STA 0xF00007EC

    LDI A, 0
    STA 0xF00007ED
    STA 0xF00007EE
    STA 0xF00007EF
    STA 0xF00007F0
    STA 0xF00007F1

    LDI A, 8
    STA 0xF00007F2      ; DiskC COMMAND = LOAD

    LDA 0xF00007F3      ; DiskC STATUS
    LDI B, 0
    CMP B
    JNZ cmd_exec_done   ; файл не найден/ошибка сборки - молча выходим

    JMP cmd_exec_run


cmd_exec_d:

    LDA cmdbuf5
    STA 0xF00007F9
    LDA cmdbuf6
    STA 0xF00007FA
    LDA cmdbuf7
    STA 0xF00007FB
    LDA cmdbuf8
    STA 0xF00007FC
    LDA cmdbuf9
    STA 0xF00007FD
    LDA cmdbuf10
    STA 0xF00007FE
    LDA cmdbuf11
    STA 0xF00007FF

    LDI A, 0
    STA 0xF0000800
    STA 0xF0000801
    STA 0xF0000802
    STA 0xF0000803
    STA 0xF0000804

    LDI A, 8
    STA 0xF0000805      ; DiskD COMMAND = LOAD

    LDA 0xF0000806      ; DiskD STATUS
    LDI B, 0
    CMP B
    JNZ cmd_exec_done

    ; --- дошли сюда после успешной сборки - запускаем, как cmd_run ---

cmd_exec_run:

    PUSH D          ; на случай, если программа испортит "константу 0"

    CALL 0x00002000

    STA savedA
    PUSH B
    POP A
    STA savedB
    PUSH C
    POP A
    STA savedC
    PUSH D
    POP A
    STA savedD

    POP D           ; восстанавливаем константу 0

    CALL goto_row_start   ; программа могла сама сдвинуть HL

cmd_exec_done:

    RET


print_char_n:

    ; Пишет значение A (символ или цвет - без разницы, просто STX) N
    ; раз подряд начиная с текущего HL, сдвигая HL. N - в tmp2.
    ; Используется для линий рамки (78 x '═') и заливки цвета
    ; (draw_banner). В отличие от print_char не трогает column - HL
    ; в местах вызова всё равно переустанавливается явно.

    STA pcn_char

pcn_loop:

    LDA tmp2
    CMP D
    JZ pcn_done

    LDI B, 1
    SUB B
    STA tmp2

    LDA pcn_char
    STX
    INCHL

    JMP pcn_loop

pcn_done:

    RET


goto_attr_row_start:

    ; То же самое, что goto_row_start, но для TextAttr (плоскость
    ; цвета) вместо Text VRAM - HL = 0xF000080C + row*80. Отдельная
    ; копия, а не параметр, т.к. подпрограммы в этом ассемблере не
    ; принимают аргументов, кроме как через регистры/DB-переменные.

    LDHL 0xF000080C

    LDA row
    STA gas_outer

gas_loop_outer:

    LDA gas_outer
    CMP D
    JZ gas_outer_done

    LDI B, 1
    SUB B
    STA gas_outer

    LDI A, 80
    STA gas_inner

gas_loop_inner:

    LDA gas_inner
    CMP D
    JZ gas_inner_done

    INCHL

    LDA gas_inner
    LDI B, 1
    SUB B
    STA gas_inner

    JMP gas_loop_inner

gas_inner_done:

    JMP gas_loop_outer

gas_outer_done:

    RET


hl_add_offset:

    ; HL уже указывает на базовый адрес, A = offset (0-255).
    ; Добавляет offset к HL через INCHL. Разрушает A, B.

    LDI B, 0
    CMP B
    JZ hl_add_offset_done   ; offset == 0 - уже на месте

hl_add_offset_loop:

    INCHL

    LDI B, 1
    SUB B

    LDI B, 0
    CMP B
    JNZ hl_add_offset_loop

hl_add_offset_done:

    RET


goto_row_start:

    ; HL = 0xF0000007 + row*80 (начало текущей строки). Нужен, чтобы
    ; вернуть курсор экрана на место после того, как HL был временно
    ; занят под чтение/запись произвольного адреса памяти (dump/poke/
    ; run) - PUSH HL не существует, поэтому пересчитываем заново.
    ;
    ; Внешний цикл - row раз, внутренний - всегда ровно 80: так можно
    ; посчитать row*80 (до 1920) без 8-битного MUL, который бы это
    ; переполнил.

    LDHL 0xF0000007

    LDA row
    STA grs_outer

grs_loop_outer:

    LDA grs_outer
    CMP D
    JZ grs_outer_done

    LDI B, 1
    SUB B
    STA grs_outer

    LDI A, 80
    STA grs_inner

grs_loop_inner:

    LDA grs_inner
    CMP D
    JZ grs_inner_done

    INCHL

    LDA grs_inner
    LDI B, 1
    SUB B
    STA grs_inner

    JMP grs_loop_inner

grs_inner_done:

    JMP grs_loop_outer

grs_outer_done:

    RET


irq_done:

    LDA 0x00010000
    LDI B, 1
    ADD B
    STA 0x00010000      ; keyCount++ (после того, как весь эффект нажатия
                     ; уже применён к VRAM - иначе main.cpp перерисует
                     ; экран до того, как символ реально записан)

    POP C
    POP B
    POP A

    RETI


; ============================================================
; Внутренние данные.
;
; Резервируются через DB, поэтому их адрес вычисляется тем же
; счётчиком, что и адреса инструкций - наложение на код исключено
; структурно, а не по договорённости.
;
; keyCount/lastKey/bannerReady/doneReady (0x00010000-0x00010003) сюда не
; входят: их напрямую читает main.cpp, который не видит меток
; ассемблера, поэтому они остаются фиксированными адресами - это
; осознанный интерфейс хост-VM, а не магический адрес наугад.
; ============================================================

quit:       DB 0
column:     DB 0
row:        DB 0
cmdlen:     DB 0
lastChar:   DB 0
currentDisk: DB 0   ; 0 = диск C, 1 = диск D (см. cmd_cd)

savedA:     DB 0
savedB:     DB 0
savedC:     DB 0
savedD:     DB 0

tmp1:       DB 0
tmp2:       DB 0

grs_outer:  DB 0
grs_inner:  DB 0

gas_outer:  DB 0   ; счётчики goto_attr_row_start (см. grs_outer/inner)
gas_inner:  DB 0

pcn_char:   DB 0   ; символ/цвет, который print_char_n сейчас печатает

; Буфер команды - 12 отдельных байт (0..11), не единый массив (см.
; комментарий в do_echo). Хватает на самую длинную команду - "poke
; NNN VVV" (12 символов).

cmdbuf0:    DB 0
cmdbuf1:    DB 0
cmdbuf2:    DB 0
cmdbuf3:    DB 0
cmdbuf4:    DB 0
cmdbuf5:    DB 0
cmdbuf6:    DB 0
cmdbuf7:    DB 0
cmdbuf8:    DB 0
cmdbuf9:    DB 0
cmdbuf10:   DB 0
cmdbuf11:   DB 0
