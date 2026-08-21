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

    LDHL 0x8000

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

    ; ---- Курсор терминала - начало второй строки ----

    LDHL 0x8050     ; 0x8000 + 80

    ; ---- Настройка клавиатуры ----

    LDI A, 1
    STA 0xF006      ; включить прерывания клавиатуры

    LDI A, 0
    STA 0x0900      ; keyCount = 0
    STA 0x0901      ; quit = 0
    STA 0x0903      ; column = 0

    LDI D, 0        ; D - константа "0" для сравнений

    LDI A, 1
    STA 0x0904      ; bannerReady = 1 (баннер готов к отрисовке)

    EI

wait:

    LDA 0x0901
    CMP D
    JZ wait

    DI
    HLT


irq_handler:

    PUSH A
    PUSH B
    PUSH C

    LDI A, 1
    STA 0xF006      ; подтвердить прерывание

    LDA 0xF005
    STA 0x0902      ; lastKey = код клавиши

    LDA 0x0900
    LDI B, 1
    ADD B
    STA 0x0900      ; keyCount++

    LDA 0x0902      ; A = код клавиши

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
    STA 0x0901      ; quit = 1
    JMP irq_done


do_echo:

    STX             ; VRAM[HL] = A (код клавиши)
    INCHL

    LDA 0x0903
    LDI B, 1
    ADD B
    STA 0x0903      ; column++

    LDI B, 80
    CMP B
    JNZ irq_done

    LDI A, 0
    STA 0x0903      ; column дошёл до 80 - перенос на новую строку

    JMP irq_done


do_backspace:

    LDA 0x0903
    LDI B, 0
    CMP B
    JZ irq_done     ; column == 0 - стирать некуда, игнорируем

    DECHL

    LDI A, 32
    STX             ; затираем символ пробелом

    LDA 0x0903
    LDI B, 1
    SUB B
    STA 0x0903      ; column--

    JMP irq_done


do_enter:

    LDA 0x0903      ; A = column
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
    STA 0x0903      ; column = 0


irq_done:

    POP C
    POP B
    POP A

    RETI
