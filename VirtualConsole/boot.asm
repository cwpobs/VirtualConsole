; ============================================================
; Стартовая программа VirtualConsole.
;
; Печатает баннер на экран (Text VRAM) и запускает интерактивный
; терминал: набранные символы отображаются на экране в реальном
; времени, Enter переводит строку, Backspace стирает символ.
; ESC завершает программу.
; ============================================================

    JMP main
    JMP irq_handler

main:

    ; ---- Баннер: "Virtual Console. ESC to quit." ----

    LDHL 0xF0000007

    LDI A, 86
    STX             ; V
    INCHL
    LDI A, 105
    STX             ; i
    INCHL
    LDI A, 114
    STX             ; r
    INCHL
    LDI A, 116
    STX             ; t
    INCHL
    LDI A, 117
    STX             ; u
    INCHL
    LDI A, 97
    STX             ; a
    INCHL
    LDI A, 108
    STX             ; l
    INCHL
    LDI A, 32
    STX             ; (пробел)
    INCHL
    LDI A, 67
    STX             ; C
    INCHL
    LDI A, 111
    STX             ; o
    INCHL
    LDI A, 110
    STX             ; n
    INCHL
    LDI A, 115
    STX             ; s
    INCHL
    LDI A, 111
    STX             ; o
    INCHL
    LDI A, 108
    STX             ; l
    INCHL
    LDI A, 101
    STX             ; e
    INCHL
    LDI A, 46
    STX             ; .
    INCHL
    LDI A, 32
    STX             ; (пробел)
    INCHL
    LDI A, 69
    STX             ; E
    INCHL
    LDI A, 83
    STX             ; S
    INCHL
    LDI A, 67
    STX             ; C
    INCHL
    LDI A, 32
    STX             ; (пробел)
    INCHL
    LDI A, 116
    STX             ; t
    INCHL
    LDI A, 111
    STX             ; o
    INCHL
    LDI A, 32
    STX             ; (пробел)
    INCHL
    LDI A, 113
    STX             ; q
    INCHL
    LDI A, 117
    STX             ; u
    INCHL
    LDI A, 105
    STX             ; i
    INCHL
    LDI A, 116
    STX             ; t
    INCHL
    LDI A, 46
    STX             ; .
    INCHL

    ; ---- Баннер: вторая строка - объём доступной RAM ----

    LDHL 0xF0000057     ; 0xF0000007 + 80 (строка 2)

    LDI A, 82
    STX             ; R
    INCHL
    LDI A, 65
    STX             ; A
    INCHL
    LDI A, 77
    STX             ; M
    INCHL
    LDI A, 58
    STX             ; :
    INCHL
    LDI A, 32
    STX             ; (пробел)
    INCHL
    LDI A, 52
    STX             ; 4
    INCHL
    LDI A, 32
    STX             ; (пробел)
    INCHL
    LDI A, 77
    STX             ; M
    INCHL
    LDI A, 66
    STX             ; B
    INCHL

    ; ---- Курсор терминала - начало третьей строки ----

    LDHL 0xF00000A7     ; 0xF0000007 + 2*80

    ; ---- Настройка клавиатуры ----

    LDI A, 1
    STA 0xF0000006      ; включить прерывания клавиатуры

    LDI A, 0
    STA 0x00001000      ; keyCount = 0
    STA quit      ; quit = 0
    STA column      ; column = 0

    LDI D, 0        ; D - константа "0" для сравнений

    LDI A, 1
    STA 0x00001002      ; bannerReady = 1 (баннер готов к отрисовке)

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

    LDI A, 75
    STX             ; K
    INCHL
    LDI A, 101
    STX             ; e
    INCHL
    LDI A, 121
    STX             ; y
    INCHL
    LDI A, 115
    STX             ; s
    INCHL
    LDI A, 58
    STX             ; :
    INCHL
    LDI A, 32
    STX             ; (пробел)
    INCHL

    LDA 0x00001000      ; keyCount
    CALL print_number

    LDI A, 1
    STA 0x00001003      ; doneReady = 1 (финальная надпись готова)

    HLT


irq_handler:

    PUSH A
    PUSH B
    PUSH C

    LDI A, 1
    STA 0xF0000006      ; подтвердить прерывание

    LDA 0xF0000005
    STA 0x00001001      ; lastKey = код клавиши

    LDA 0x00001001      ; A = код клавиши

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

    STX             ; VRAM[HL] = A (код клавиши)
    INCHL

    LDA column
    LDI B, 1
    ADD B
    STA column      ; column++

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

    JMP irq_done


do_enter:

    LDA column      ; A = column
    PUSH A
    POP B           ; B = column

    LDI A, 80
    SUB B           ; A = 80 - column (сколько ячеек до начала след. строки)

    LDI C, 1

newline_loop:

    INCHL
    SUB C
    CMP D
    JNZ newline_loop

    LDI A, 0
    STA column      ; column = 0

    CALL advance_row

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
    STA 0xF00007D7      ; SCROLL - сдвинуть экран на одну строку вверх

    LDHL 0xF0000787     ; последняя строка (24), столбец 0 (0xF0000007 + 24*80)

    LDI A, 24
    STA row

advance_row_done:

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
    STX
    INCHL

    JMP pn_print

pn_done:

    POP D
    POP B
    RET


irq_done:

    LDA 0x00001000
    LDI B, 1
    ADD B
    STA 0x00001000      ; keyCount++ (после того, как весь эффект нажатия
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
; keyCount/lastKey/bannerReady/doneReady (0x00001000-0x00001003) сюда не
; входят: их напрямую читает main.cpp, который не видит меток
; ассемблера, поэтому они остаются фиксированными адресами - это
; осознанный интерфейс хост-VM, а не магический адрес наугад.
; ============================================================

quit:       DB 0
column:     DB 0
row:        DB 0
