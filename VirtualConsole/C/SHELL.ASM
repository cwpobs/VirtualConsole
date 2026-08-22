; ============================================================
; SHELL.ASM - резидентная "операционная система" VirtualConsole.
;
; Загружается и запускается минимальным boot.asm (см. boot.asm в
; корне проекта) через Disk.LOAD_SHELL (COMMAND=10) на фиксированный
; адрес 0x00003000 - см. ASSEMBLY.md, "Disk" и "Структура программы".
; Этот файл не начинается с обычной таблицы векторов (JMP main/JMP
; irq_handler) - код грузится не на адрес 0, а вектор прерывания
; (жёстко зашитый CPU на 0x00000005) патчится вручную ниже, при
; старте main.
;
; Печатает баннер на экран (Text VRAM) и запускает интерактивный
; терминал: набранные символы отображаются на экране в реальном
; времени, Enter переводит строку, Backspace стирает символ.
; Ctrl+Q завершает программу.
;
; Терминал также работает как простой командный shell: строка,
; набранная до Enter, сравнивается с одной из известных команд
; (help/cls/regs/dump/poke/run/reset/dir/type/cd/exec/create/del/
; copy) и выполняется - см. dispatch_command и обработчики cmd_*
; ниже.
;
; Можно редактировать этот файл и просто перезапускать VM - без
; пересборки C++-проекта: boot.asm каждый раз заново собирает его
; хостовым ассемблером через Disk.LOAD_SHELL.
; ============================================================

main:

    ; ---- Патчим вектор прерывания (0x00000005) на свой irq_handler ----
    ;
    ; CPU при прерывании ВСЕГДА прыгает на фиксированный адрес
    ; 0x00000005 (CPU::INTERRUPT_VECTOR), независимо от того, что
    ; сейчас исполняется. Раз этот код живёт не на адресе 0 (а на
    ; 0x00003000), нужно самим положить туда "JMP irq_handler" -
    ; иначе клавиатура никогда не достучится до shell'а.
    ;
    ; LDHL резолвит адрес МЕТКИ (ассемблер это уже умеет), DebugPort
    ; даёт прочитать HL обратно по байтам - так собираем 5 байт
    ; "JMP <адрес irq_handler>" и кладём их по адресу 5 через STA.

    LDHL irq_handler

    LDI A, 0x07         ; опкод JMP
    STA 0x00000005

    LDA 0xF00007E1      ; DebugPort: младший байт HL
    STA 0x00000006
    LDA 0xF00007E2
    STA 0x00000007
    LDA 0xF00007E3
    STA 0x00000008
    LDA 0xF00007E4
    STA 0x00000009

    ; ---- Патчим точку входа "запустить дочернюю программу" (0x0000000A) ----
    ;
    ; Мини-C builtin exec_child() (см. Compiler.cpp, ASSEMBLY.md) не
    ; знает адрес песочницы и не решает, какой уровень вложенности
    ; сейчас идёт - он просто "CALL 0x0000000A", ровно как CPU при
    ; прерывании просто прыгает на 0x00000005. Здесь, тем же способом
    ; (LDHL метки + DebugPort + STA), кладём по 0x0000000A "JMP
    ; shell_exec_child" - реальную логику выбора адреса/команды диска
    ; по глубине вложенности (см. shell_exec_child ниже).

    LDHL shell_exec_child

    LDI A, 0x07         ; опкод JMP
    STA 0x0000000A

    LDA 0xF00007E1
    STA 0x0000000B
    LDA 0xF00007E2
    STA 0x0000000C
    LDA 0xF00007E3
    STA 0x0000000D
    LDA 0xF00007E4
    STA 0x0000000E

    LDI A, 0
    STA 0x0000000F      ; EXEC_CHILD_DISK - какой диск (0=C,1=D) держит имя запускаемой программы

    CALL draw_banner

    ; ---- Настройка клавиатуры ----

    LDI A, 1
    STA 0xF0000006      ; включить прерывания клавиатуры

    LDI A, 0
    STA 0x00010000      ; keyCount = 0
    STA quit            ; quit = 0
    STA cmdlen          ; cmdlen = 0
    STA 0x00010004      ; programRunning = 0

    LDI A, 1
    STA execDepth       ; execDepth = 1 - работает только "shell -> X" (см. shell_exec_child)

    LDI D, 0        ; D - константа "0" для сравнений на весь запуск

    LDI A, 0
    STA dirDepth    ; стартуем в корне диска C

    CALL print_prompt

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

    ; Пока выполняется программа (exec/run/FM.MC/вложенный exec_child -
    ; см. programRunning, общий на всю глубину вложенности, не только
    ; на execDepth==1) - собственный ввод команд шелла (echo символов,
    ; Enter->dispatch_command, Backspace) должен быть полностью
    ; приостановлен: работающая программа сама вычитывает lastKey в
    ; своём цикле опроса (см. комментарий в do_quit ниже - раньше эта
    ; логика была реализована ТОЛЬКО для Ctrl+Q). Без этой проверки
    ; ЛЮБАЯ клавиша, нажатая, пока программа с EI работает (графические
    ; демки и т.п.), реентрантно копится в cmdbuf и на Enter повторно
    ; запускает dispatch_command поверх ещё не завершившегося внешнего
    ; вызова - именно так ломались повторные запуски графических
    ; демок, "неправильная" навигация шелла по папкам и крах FM вместе
    ; с дочерней программой прямо в шелл.

    LDA 0x00010004      ; programRunning
    LDI B, 0
    CMP B
    JNZ irq_done

    LDA 0x00010001      ; A = код клавиши

    LDI B, 17       ; Ctrl+Q
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

    ; Если сейчас выполняется программа (exec/run - см. programRunning
    ; в cmd_run/cmd_exec_run), Ctrl+Q не должен гасить всю VM - lastKey
    ; уже обновлён выше безусловно, программа сама заметит его в своём
    ; цикле опроса и завершится штатно, вернувшись в шелл.
    LDA 0x00010004      ; programRunning
    LDI B, 0
    CMP B
    JNZ irq_done

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
    JNZ de_check12
    LDA lastChar
    STA cmdbuf11
    JMP de_buf_done

de_check12:
    LDA cmdlen
    LDI B, 12
    CMP B
    JNZ de_check13
    LDA lastChar
    STA cmdbuf12
    JMP de_buf_done

de_check13:
    LDA cmdlen
    LDI B, 13
    CMP B
    JNZ de_check14
    LDA lastChar
    STA cmdbuf13
    JMP de_buf_done

de_check14:
    LDA cmdlen
    LDI B, 14
    CMP B
    JNZ de_check15
    LDA lastChar
    STA cmdbuf14
    JMP de_buf_done

de_check15:
    LDA cmdlen
    LDI B, 15
    CMP B
    JNZ de_check16
    LDA lastChar
    STA cmdbuf15
    JMP de_buf_done

de_check16:
    LDA cmdlen
    LDI B, 16
    CMP B
    JNZ de_check17
    LDA lastChar
    STA cmdbuf16
    JMP de_buf_done

de_check17:
    LDA cmdlen
    LDI B, 17
    CMP B
    JNZ de_check18
    LDA lastChar
    STA cmdbuf17
    JMP de_buf_done

de_check18:
    LDA cmdlen
    LDI B, 18
    CMP B
    JNZ de_check19
    LDA lastChar
    STA cmdbuf18
    JMP de_buf_done

de_check19:
    LDA cmdlen
    LDI B, 19
    CMP B
    JNZ de_check20
    LDA lastChar
    STA cmdbuf19
    JMP de_buf_done

; ---- cmdbuf20..35 - расширение под аргументы командной строки (см.
; ASSEMBLY.md, "Аргументы командной строки" - "exec ИМЯ АРГУМЕНТ") - тот
; же механический приём, что и cmdbuf0..19 выше, просто продолжен дальше.

de_check20:
    LDA cmdlen
    LDI B, 20
    CMP B
    JNZ de_check21
    LDA lastChar
    STA cmdbuf20
    JMP de_buf_done

de_check21:
    LDA cmdlen
    LDI B, 21
    CMP B
    JNZ de_check22
    LDA lastChar
    STA cmdbuf21
    JMP de_buf_done

de_check22:
    LDA cmdlen
    LDI B, 22
    CMP B
    JNZ de_check23
    LDA lastChar
    STA cmdbuf22
    JMP de_buf_done

de_check23:
    LDA cmdlen
    LDI B, 23
    CMP B
    JNZ de_check24
    LDA lastChar
    STA cmdbuf23
    JMP de_buf_done

de_check24:
    LDA cmdlen
    LDI B, 24
    CMP B
    JNZ de_check25
    LDA lastChar
    STA cmdbuf24
    JMP de_buf_done

de_check25:
    LDA cmdlen
    LDI B, 25
    CMP B
    JNZ de_check26
    LDA lastChar
    STA cmdbuf25
    JMP de_buf_done

de_check26:
    LDA cmdlen
    LDI B, 26
    CMP B
    JNZ de_check27
    LDA lastChar
    STA cmdbuf26
    JMP de_buf_done

de_check27:
    LDA cmdlen
    LDI B, 27
    CMP B
    JNZ de_check28
    LDA lastChar
    STA cmdbuf27
    JMP de_buf_done

de_check28:
    LDA cmdlen
    LDI B, 28
    CMP B
    JNZ de_check29
    LDA lastChar
    STA cmdbuf28
    JMP de_buf_done

de_check29:
    LDA cmdlen
    LDI B, 29
    CMP B
    JNZ de_check30
    LDA lastChar
    STA cmdbuf29
    JMP de_buf_done

de_check30:
    LDA cmdlen
    LDI B, 30
    CMP B
    JNZ de_check31
    LDA lastChar
    STA cmdbuf30
    JMP de_buf_done

de_check31:
    LDA cmdlen
    LDI B, 31
    CMP B
    JNZ de_check32
    LDA lastChar
    STA cmdbuf31
    JMP de_buf_done

de_check32:
    LDA cmdlen
    LDI B, 32
    CMP B
    JNZ de_check33
    LDA lastChar
    STA cmdbuf32
    JMP de_buf_done

de_check33:
    LDA cmdlen
    LDI B, 33
    CMP B
    JNZ de_check34
    LDA lastChar
    STA cmdbuf33
    JMP de_buf_done

de_check34:
    LDA cmdlen
    LDI B, 34
    CMP B
    JNZ de_check35
    LDA lastChar
    STA cmdbuf34
    JMP de_buf_done

de_check35:
    LDA cmdlen
    LDI B, 35
    CMP B
    JNZ de_buf_done
    LDA lastChar
    STA cmdbuf35

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

    CALL print_prompt

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

    ; ---- Строка 1: "Shell v1.0 (2026). Ctrl+Q to quit." ----

    LDHL 0xF0000057     ; 0xF0000007 + 80
    LDI A, 0
    STA column
    LDI A, 1
    STA row

    LDI A, 0xBA
    CALL print_char   ; ║

    LDI A, 83
    CALL print_char   ; S
    LDI A, 104
    CALL print_char   ; h
    LDI A, 101
    CALL print_char   ; e
    LDI A, 108
    CALL print_char   ; l
    LDI A, 108
    CALL print_char   ; l
    LDI A, 32
    CALL print_char   ; (пробел)
    LDI A, 118
    CALL print_char   ; v
    LDI A, 49
    CALL print_char   ; 1
    LDI A, 46
    CALL print_char   ; .
    LDI A, 48
    CALL print_char   ; 0
    LDI A, 32
    CALL print_char   ; (пробел)
    LDI A, 40
    CALL print_char   ; (
    LDI A, 50
    CALL print_char   ; 2
    LDI A, 48
    CALL print_char   ; 0
    LDI A, 50
    CALL print_char   ; 2
    LDI A, 54
    CALL print_char   ; 6
    LDI A, 41
    CALL print_char   ; )
    LDI A, 46
    CALL print_char   ; .
    LDI A, 32
    CALL print_char   ; (пробел)
    LDI A, 67
    CALL print_char   ; C
    LDI A, 116
    CALL print_char   ; t
    LDI A, 114
    CALL print_char   ; r
    LDI A, 108
    CALL print_char   ; l
    LDI A, 43
    CALL print_char   ; +
    LDI A, 81
    CALL print_char   ; Q
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

    ; 34 видимых символа - дополняем пробелами до 78
    LDI A, 44
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


print_prompt:

    ; Промпт в стиле DOS: "C:\>" в корне, "C:\A\B\C>" на глубине 3 и
    ; т.д. (см. dirDepth/dirNames, устанавливаются cmd_cd*). Заменяет
    ; прежний статичный "> ".

    LDA currentDisk
    CMP D
    JNZ pp_drive_d

    LDI A, 67    ; 'C'
    CALL print_char
    JMP pp_colon

pp_drive_d:

    LDI A, 68    ; 'D'
    CALL print_char

pp_colon:

    LDI A, 58    ; ':'
    CALL print_char
    LDI A, 92    ; '\'
    CALL print_char

    LDA dirDepth
    CMP D
    JZ pp_done   ; в корне - имена папок не печатаем

    LDI A, 0
    STA ppLevel

pp_level_loop:

    ; цикл, пока ppLevel < dirDepth
    LDA dirDepth
    PUSH A
    LDA ppLevel
    POP B
    CMP B                 ; CARRY=1, если ppLevel < dirDepth
    JNC pp_levels_done

    ; разделитель "\" перед каждым уровнем, КРОМЕ самого первого - до
    ; него уже напечатан "\" сразу после буквы диска
    LDA ppLevel
    CMP D
    JZ pp_no_sep
    LDI A, 92    ; '\'
    CALL print_char
pp_no_sep:

    LDI A, 0
    STA ppChar

pp_char_loop:

    ; напечатать до 12 символов имени уровня, остановиться на первом 0
    LDA ppChar
    LDI B, 12
    CMP B
    JZ pp_char_done

    ; HL нужен для двух разных вещей - курсор экрана (print_char) и
    ; чтение dirNames - PUSH HL не существует (см. goto_row_start),
    ; поэтому каждый раз пересчитываем HL заново под то, что сейчас
    ; нужно, а не пытаемся его "сохранить".
    LDHL dirNames
    LDA ppLevel
    LDI B, 12
    MUL B
    PUSH A
    LDA ppChar
    POP B
    ADD B                 ; A = ppLevel*12 + ppChar (макс. 7*12+11=95)
    CALL hl_add_offset     ; HL = dirNames + смещение

    LDX                    ; A = символ имени
    CMP D
    JZ pp_char_done        ; 0 - конец имени этого уровня

    STA ppByte             ; отложить символ, пока пересчитываем HL под экран

    CALL goto_row_start
    LDA column
    CALL hl_add_offset     ; HL = текущая позиция курсора на экране

    LDA ppByte
    CALL print_char         ; печатает A, сам сдвигает HL/column

    LDA ppChar
    LDI B, 1
    ADD B
    STA ppChar
    JMP pp_char_loop

pp_char_done:

    ; Сюда попадаем и найдя 0 (конец имени - HL ещё указывает В
    ; dirNames, не на экран!), и исчерпав 12 символов (HL уже на
    ; экране от последнего print_char, но лишний пересчёт безвреден) -
    ; в ОБОИХ случаях гарантируем HL на экране перед тем, как дальше
    ; печатать "\" следующего уровня или ">" (баг был именно тут -
    ; ">" улетал в dirNames вместо экрана, живым тестом нашли).
    CALL goto_row_start
    LDA column
    CALL hl_add_offset

    LDA ppLevel
    LDI B, 1
    ADD B
    STA ppLevel
    JMP pp_level_loop

pp_levels_done:

pp_done:

    LDI A, 62    ; '>'
    CALL print_char

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

    ; "type " + имя файла, переменная длина 1-12 символов (настоящий
    ; 8.3) - диапазон проверяем через CARRY (CMP выставляет его как
    ; "A < B"), само имя копирует copy_name_to_disk*.

    LDA cmdlen
    LDI B, 6        ; минимум: "type " (5) + 1 символ
    CMP B
    JC check_cd

    LDA cmdlen
    LDI B, 18       ; максимум: "type " (5) + 12 символов = 17
    CMP B
    JNC check_cd

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

    ; "cd c" / "cd d" (4 символа) - переключение диска (см. cmd_cd)

    LDA cmdlen
    LDI B, 4
    CMP B
    JNZ check_cd_up

    LDA cmdbuf0
    LDI B, 99       ; 'c'
    CMP B
    JNZ check_cd_up
    LDA cmdbuf1
    LDI B, 100      ; 'd'
    CMP B
    JNZ check_cd_up
    LDA cmdbuf2
    LDI B, 32       ; (пробел)
    CMP B
    JNZ check_cd_up

    CALL cmd_cd
    JMP dispatch_done


check_cd_up:

    ; "cd.." (4 символа, без пробела) - выйти из папки на уровень выше

    LDA cmdlen
    LDI B, 4
    CMP B
    JNZ check_cd_dir

    LDA cmdbuf0
    LDI B, 99       ; 'c'
    CMP B
    JNZ check_cd_dir
    LDA cmdbuf1
    LDI B, 100      ; 'd'
    CMP B
    JNZ check_cd_dir
    LDA cmdbuf2
    LDI B, 46       ; '.'
    CMP B
    JNZ check_cd_dir
    LDA cmdbuf3
    LDI B, 46       ; '.'
    CMP B
    JNZ check_cd_dir

    CALL cmd_cd_up
    JMP dispatch_done


check_cd_dir:

    ; "cd " + имя папки, переменная длина 1-12 символов (та же схема,
    ; что у type/exec/create). Не пересекается с "cd c"/"cd d"/"cd.." -
    ; те проверяются раньше и явно совпадают только на точный текст.

    LDA cmdlen
    LDI B, 4        ; "cd " (3) + 1 символ
    CMP B
    JC check_exec

    LDA cmdlen
    LDI B, 16       ; "cd " (3) + 12 символов = 15
    CMP B
    JNC check_exec

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

    CALL cmd_cd_dir
    JMP dispatch_done


check_exec:

    ; "exec " + имя файла (1-12 символов) + необязательный " " + аргумент
    ; (0-16 символов, см. ASSEMBLY.md, "Аргументы командной строки") -
    ; верхняя граница 36 = "exec "(5) + имя(12) + " "(1) + аргумент(16) +
    ; 2 байта запаса, а не строго 18 как раньше (когда аргументов не
    ; было). Сам разбор имени/аргумента - find_name_and_arg_len, см.
    ; cmd_exec.

    LDA cmdlen
    LDI B, 6
    CMP B
    JC check_create

    LDA cmdlen
    LDI B, 36
    CMP B
    JNC check_create

    LDA cmdbuf0
    LDI B, 101      ; 'e'
    CMP B
    JNZ check_create
    LDA cmdbuf1
    LDI B, 120      ; 'x'
    CMP B
    JNZ check_create
    LDA cmdbuf2
    LDI B, 101      ; 'e'
    CMP B
    JNZ check_create
    LDA cmdbuf3
    LDI B, 99       ; 'c'
    CMP B
    JNZ check_create
    LDA cmdbuf4
    LDI B, 32       ; (пробел)
    CMP B
    JNZ check_create

    CALL cmd_exec
    JMP dispatch_done


check_create:

    ; "create " + имя файла, переменная длина 1-12 символов

    LDA cmdlen
    LDI B, 8        ; "create " (7) + 1 символ
    CMP B
    JC check_del

    LDA cmdlen
    LDI B, 20       ; "create " (7) + 12 символов = 19
    CMP B
    JNC check_del

    LDA cmdbuf0
    LDI B, 99       ; 'c'
    CMP B
    JNZ check_del
    LDA cmdbuf1
    LDI B, 114      ; 'r'
    CMP B
    JNZ check_del
    LDA cmdbuf2
    LDI B, 101      ; 'e'
    CMP B
    JNZ check_del
    LDA cmdbuf3
    LDI B, 97       ; 'a'
    CMP B
    JNZ check_del
    LDA cmdbuf4
    LDI B, 116      ; 't'
    CMP B
    JNZ check_del
    LDA cmdbuf5
    LDI B, 101      ; 'e'
    CMP B
    JNZ check_del
    LDA cmdbuf6
    LDI B, 32       ; (пробел)
    CMP B
    JNZ check_del

    CALL cmd_create
    JMP dispatch_done


check_del:

    ; "del " + имя файла, переменная длина 1-12 символов

    LDA cmdlen
    LDI B, 5        ; "del " (4) + 1 символ
    CMP B
    JC check_copy

    LDA cmdlen
    LDI B, 17       ; "del " (4) + 12 символов = 16
    CMP B
    JNC check_copy

    LDA cmdbuf0
    LDI B, 100      ; 'd'
    CMP B
    JNZ check_copy
    LDA cmdbuf1
    LDI B, 101      ; 'e'
    CMP B
    JNZ check_copy
    LDA cmdbuf2
    LDI B, 108      ; 'l'
    CMP B
    JNZ check_copy
    LDA cmdbuf3
    LDI B, 32       ; (пробел)
    CMP B
    JNZ check_copy

    CALL cmd_del
    JMP dispatch_done


check_copy:

    ; "copy " + имя файла, переменная длина 1-12 символов - копирует
    ; между дисками C/D под тем же именем (см. cmd_copy)

    LDA cmdlen
    LDI B, 6        ; "copy " (5) + 1 символ
    CMP B
    JC check_build

    LDA cmdlen
    LDI B, 18       ; "copy " (5) + 12 символов = 17
    CMP B
    JNC check_build

    LDA cmdbuf0
    LDI B, 99       ; 'c'
    CMP B
    JNZ check_build
    LDA cmdbuf1
    LDI B, 111      ; 'o'
    CMP B
    JNZ check_build
    LDA cmdbuf2
    LDI B, 112      ; 'p'
    CMP B
    JNZ check_build
    LDA cmdbuf3
    LDI B, 121      ; 'y'
    CMP B
    JNZ check_build
    LDA cmdbuf4
    LDI B, 32       ; (пробел)
    CMP B
    JNZ check_build

    CALL cmd_copy
    JMP dispatch_done


check_build:

    ; "build " + имя .asm-файла, переменная длина 1-12 символов -
    ; собирает его в ИМЯ.RUN (см. cmd_build, Disk.BUILD=14)

    LDA cmdlen
    LDI B, 7        ; "build " (6) + 1 символ
    CMP B
    JC check_autorun

    LDA cmdlen
    LDI B, 19       ; "build " (6) + 12 символов = 18
    CMP B
    JNC check_autorun

    LDA cmdbuf0
    LDI B, 98       ; 'b'
    CMP B
    JNZ check_autorun
    LDA cmdbuf1
    LDI B, 117      ; 'u'
    CMP B
    JNZ check_autorun
    LDA cmdbuf2
    LDI B, 105      ; 'i'
    CMP B
    JNZ check_autorun
    LDA cmdbuf3
    LDI B, 108      ; 'l'
    CMP B
    JNZ check_autorun
    LDA cmdbuf4
    LDI B, 100      ; 'd'
    CMP B
    JNZ check_autorun
    LDA cmdbuf5
    LDI B, 32       ; (пробел)
    CMP B
    JNZ check_autorun

    CALL cmd_build
    JMP dispatch_done


check_autorun:

    ; Ничего из известных команд не совпало - последняя попытка:
    ; считаем всю введённую строку именем программы и пробуем
    ; запустить ИМЯ.RUN (см. cmd_autorun) - как .exe/.com в DOS. Не
    ; сравнение, а безусловный переход - cmd_autorun сам решает,
    ; получилось или нет, и тихо выходит, если ИМЯ.RUN не нашёлся
    ; (тогда строка просто выглядит как неизвестная команда).

    CALL cmd_autorun

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
    CALL print_char   ; N (имя файла, 1-12 символов - настоящий 8.3)

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

    LDI A, 99
    CALL print_char   ; c
    LDI A, 100
    CALL print_char   ; d
    LDI A, 32
    CALL print_char
    LDI A, 78
    CALL print_char   ; N (имя папки)

    CALL print_newline

    LDI A, 99
    CALL print_char   ; c
    LDI A, 100
    CALL print_char   ; d
    LDI A, 46
    CALL print_char   ; .
    LDI A, 46
    CALL print_char   ; . (выйти из папки на уровень выше)

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
    CALL print_char   ; N

    CALL print_newline

    LDI A, 99
    CALL print_char   ; c
    LDI A, 114
    CALL print_char   ; r
    LDI A, 101
    CALL print_char   ; e
    LDI A, 97
    CALL print_char   ; a
    LDI A, 116
    CALL print_char   ; t
    LDI A, 101
    CALL print_char   ; e
    LDI A, 32
    CALL print_char
    LDI A, 78
    CALL print_char   ; N

    CALL print_newline

    LDI A, 100
    CALL print_char   ; d
    LDI A, 101
    CALL print_char   ; e
    LDI A, 108
    CALL print_char   ; l
    LDI A, 32
    CALL print_char
    LDI A, 78
    CALL print_char   ; N

    CALL print_newline

    LDI A, 99
    CALL print_char   ; c
    LDI A, 111
    CALL print_char   ; o
    LDI A, 112
    CALL print_char   ; p
    LDI A, 121
    CALL print_char   ; y
    LDI A, 32
    CALL print_char
    LDI A, 78
    CALL print_char   ; N

    CALL print_newline

    LDI A, 98
    CALL print_char   ; b
    LDI A, 117
    CALL print_char   ; u
    LDI A, 105
    CALL print_char   ; i
    LDI A, 108
    CALL print_char   ; l
    LDI A, 100
    CALL print_char   ; d
    LDI A, 32
    CALL print_char
    LDI A, 78
    CALL print_char   ; N

    CALL print_newline

    LDI A, 78
    CALL print_char   ; N
    LDI A, 46
    CALL print_char   ; .
    LDI A, 114
    CALL print_char   ; r
    LDI A, 117
    CALL print_char   ; u
    LDI A, 110
    CALL print_char   ; n

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


shell_exec_child:

    ; Системный вызов "запустить дочернюю программу" - точка входа
    ; 0x0000000A (см. main, патч в начале файла), вызывается Мини-C
    ; builtin'ом exec_child() (см. Compiler.cpp, ASSEMBLY.md) из ЛЮБОЙ
    ; уже выполняющейся программы (сейчас - FM.MC, но не только). Сама
    ; программа НЕ решает, по какому адресу грузить дочерний *.RUN -
    ; только кладёт диск с именем файла в NAME в EXEC_CHILD_DISK
    ; (0x0000000F, 0=C, 1=D) и делает CALL сюда.
    ;
    ; execDepth - текущая глубина вложенности (1 = обычная "shell -> X"
    ; программа, ещё не звала exec_child()). Каждому следующему уровню
    ; - своя команда диска и свой адрес песочницы (см. Disk.h,
    ; EXEC_CHILD_DEPTHn_ADDRESS) - RAM много (4 МиБ), эти адреса лежат
    ; далеко от LOAD_ADDRESS/SHELL_LOAD_ADDRESS и друг от друга, экономить
    ; незачем. Глубже 5 не поддержано - тихий отказ, как и при
    ; отсутствии .REL/файла.

    PUSH D          ; на случай, если дочерняя программа испортит "константу 0"

    LDA execDepth
    LDI B, 1
    ADD B
    STA execDepth

    LDA execDepth
    LDI B, 2
    CMP B
    JZ sec_cmd15
    LDA execDepth
    LDI B, 3
    CMP B
    JZ sec_cmd16
    LDA execDepth
    LDI B, 4
    CMP B
    JZ sec_cmd17
    LDA execDepth
    LDI B, 5
    CMP B
    JZ sec_cmd18

    JMP sec_fail    ; глубже 5 не поддержано

sec_cmd15:
    LDI A, 15
    STA sec_cmdValue
    JMP sec_have_cmd
sec_cmd16:
    LDI A, 16
    STA sec_cmdValue
    JMP sec_have_cmd
sec_cmd17:
    LDI A, 17
    STA sec_cmdValue
    JMP sec_have_cmd
sec_cmd18:
    LDI A, 18
    STA sec_cmdValue

sec_have_cmd:

    LDA 0x0000000F      ; EXEC_CHILD_DISK
    LDI B, 0
    CMP B
    JNZ sec_disk_d

    LDA sec_cmdValue
    STA 0xF00007F2      ; DiskC COMMAND
    LDA 0xF00007F3      ; DiskC STATUS
    JMP sec_check_status

sec_disk_d:
    LDA sec_cmdValue
    STA 0xF0000805      ; DiskD COMMAND
    LDA 0xF0000806      ; DiskD STATUS

sec_check_status:

    LDI B, 2
    CMP B
    JZ sec_fail     ; не найден/не собран (нет .REL и т.п.) - молча отказываем

    ; Адрес CALL - тот же execDepth. DI перед входом во вложенный
    ; уровень - явная гарантия известного состояния прерываний на
    ; границе вызова (дочерняя программа сама решает, звать ли EI, и
    ; обязана сделать DI перед своим RET - см. CUBE3D.ASM/TILEDEMO.ASM/
    ; MUSIC.ASM).

    LDI A, 0
    STA 0x00010001      ; lastKey = 0 - свежий старт (см. cmd_run) -
                        ; иначе дочерняя программа, сравнивающая
                        ; lastKey с кодом клавиши в своём цикле опроса,
                        ; увидит СТАРОЕ значение от ПРЕДЫДУЩЕГО запуска
                        ; и выйдет мгновенно, ни разу не увидев
                        ; настоящего нажатия - а клавиша, нажатая уже
                        ; ПОСЛЕ этого для неё, окажется никем не
                        ; съеденной и "провалится" в того, кто её
                        ; вызвал (например, FM.MC тоже увидит Ctrl+Q и
                        ; выйдет сам)

    LDA execDepth
    LDI B, 2
    CMP B
    JZ sec_addr2
    LDA execDepth
    LDI B, 3
    CMP B
    JZ sec_addr3
    LDA execDepth
    LDI B, 4
    CMP B
    JZ sec_addr4

    DI
    CALL 0x001C0000     ; EXEC_CHILD_DEPTH5_ADDRESS
    JMP sec_after_call

sec_addr2:
    DI
    CALL 0x00100000     ; EXEC_CHILD_DEPTH2_ADDRESS
    JMP sec_after_call
sec_addr3:
    DI
    CALL 0x00140000     ; EXEC_CHILD_DEPTH3_ADDRESS
    JMP sec_after_call
sec_addr4:
    DI
    CALL 0x00180000     ; EXEC_CHILD_DEPTH4_ADDRESS

sec_after_call:

    LDA execDepth
    LDI B, 1
    SUB B
    STA execDepth

    POP D
    RET

sec_fail:

    LDA execDepth
    LDI B, 1
    SUB B
    STA execDepth

    POP D
    RET


cmd_run:

    PUSH D          ; на случай, если код в песочнице испортит "константу 0"

    LDI A, 1
    STA 0x00010004        ; programRunning = 1 - Ctrl+Q во время работы
                          ; программы не должен гасить всю VM - см.
                          ; do_quit; main.cpp тоже читает этот адрес,
                          ; чтобы включать перерисовку по таймеру
                          ; только пока реально работает программа

    LDI A, 0
    STA 0x00010001        ; lastKey = 0 - свежий старт: иначе программа,
                          ; которая в цикле опроса сравнивает lastKey с
                          ; кодом клавиши (например Ctrl+Q=17), увидит
                          ; СТАРОЕ значение, оставшееся от ПРЕДЫДУЩЕГО
                          ; запуска, и выйдет мгновенно, даже не увидев
                          ; ни одного реального нажатия - именно так
                          ; повторный запуск программы "не запускался"
                          ; и лишний Ctrl+Q "проваливался" в того, кто
                          ; её вызвал (см. shell_exec_child ниже - там
                          ; та же проблема и тот же фикс)

    CALL 0x00002000

    PUSH A                ; сохранить A программы на время сброса флага
    LDI A, 0
    STA 0x00010004        ; programRunning = 0
    POP A

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

    ; сброс в корень на любой глубине - см. cmd_cd_reset_current
    ; (общая с cmd_cd): поднимает currentDisk в корень CHDIR_UP'ом
    ; dirDepth раз и сама обнуляет dirDepth.

    CALL cmd_cd_reset_current

    LDI A, 0
    STA currentDisk

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

    ; "type ИМЯ" - ИМЯ теперь переменной длины (1-12 символов, см.
    ; check_type) - копирует copy_name_to_diskc.

    LDI A, 5
    STA cn_prefix_len   ; длина префикса "type "
    CALL find_name_and_arg_len
    CALL copy_name_to_diskc

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

    LDI A, 5
    STA cn_prefix_len   ; длина префикса "type "
    CALL find_name_and_arg_len
    CALL copy_name_to_diskd

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
    ; dir/type/... Символ диска - cmdbuf3. Заодно возвращает В КОРЕНЬ
    ; диск, на котором стояли ДО переключения (v1 не помнит "где был"
    ; на каждом диске отдельно) - dirDepth относится именно к нему,
    ; не к тому, на который переключаемся (тот и так уже в корне - на
    ; нём ещё не были). CHDIR_UP поднимает только на один уровень за
    ; раз, поэтому cmd_cd_reset_current (общая с cmd_reset) - цикл по
    ; dirDepth ДО того, как currentDisk поменяется.

    CALL cmd_cd_reset_current

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


cmd_cd_reset_current:

    ; Общая для cmd_cd (смена диска) и cmd_reset - поднимает диск,
    ; который СЕЙЧАС является currentDisk, в корень (CHDIR_UP
    ; dirDepth раз - у Disk нет "сразу в корень"), обнуляет dirDepth.
    ; Вызывать ДО смены currentDisk.

    LDA currentDisk
    CMP D
    JNZ ccrc_d_loop

ccrc_c_loop:

    LDA dirDepth
    CMP D
    JZ ccrc_done

    LDI A, 12
    STA 0xF00007F2      ; DiskC COMMAND = CHDIR_UP

    LDA dirDepth
    LDI B, 1
    SUB B
    STA dirDepth

    JMP ccrc_c_loop

ccrc_d_loop:

    LDA dirDepth
    CMP D
    JZ ccrc_done

    LDI A, 12
    STA 0xF0000805      ; DiskD COMMAND = CHDIR_UP

    LDA dirDepth
    LDI B, 1
    SUB B
    STA dirDepth

    JMP ccrc_d_loop

ccrc_done:

    LDI A, 0
    STA dirDepth

    RET


cmd_cd_up:

    ; "cd.." - выйти из папки на уровень выше (на currentDisk).
    ; dirDepth - общий счётчик глубины для промпта (не по дискам,
    ; как и currentDisk/CHDIR сам по себе).

    LDA dirDepth
    CMP D
    JZ cmd_cd_up_done   ; уже в корне - ничего не делаем (как в DOS)

    LDA currentDisk
    CMP D
    JNZ cmd_cd_up_d

    LDI A, 12
    STA 0xF00007F2      ; DiskC COMMAND = CHDIR_UP
    JMP cmd_cd_up_after

cmd_cd_up_d:

    LDI A, 12
    STA 0xF0000805      ; DiskD COMMAND = CHDIR_UP

cmd_cd_up_after:

    LDA dirDepth
    LDI B, 1
    SUB B
    STA dirDepth

cmd_cd_up_done:

    RET


cmd_cd_dir:

    ; "cd ИМЯ" - зайти в папку ИМЯ на currentDisk (CHDIR = 11 в Disk)

    LDA currentDisk
    CMP D
    JNZ cmd_cd_dir_d
    JMP cmd_cd_dir_c


cmd_cd_dir_c:

    ; dirDepth - общий счётчик глубины, используемый ТОЛЬКО промптом
    ; (см. print_prompt) - сам Disk::currentDir глубину не ограничивает
    ; вообще, ограничение только на размер стека имён здесь, в шелле.

    LDA dirDepth
    LDI B, 8
    CMP B
    JNC cmd_cd_dir_done   ; уже на пределе глубины - молча отказываем,
                          ; как "папка не найдена" - CHDIR даже не
                          ; пробуем, чтобы Disk и промпт не разошлись

    LDI A, 3
    STA cn_prefix_len   ; длина префикса "cd "
    CALL find_name_and_arg_len
    CALL copy_name_to_diskc

    LDI A, 11
    STA 0xF00007F2      ; DiskC COMMAND = CHDIR

    LDA 0xF00007F3      ; DiskC STATUS
    LDI B, 0
    CMP B
    JNZ cmd_cd_dir_done  ; не папка/не найдена - молча выходим

    ; успех - копируем имя из NAME диска C в dirNames[dirDepth*12..+11]
    ; для промпта (см. print_prompt)

    LDHL dirNames
    LDA dirDepth
    LDI B, 12
    MUL B
    CALL hl_add_offset    ; HL = dirNames + dirDepth*12

    LDA 0xF00007E6
    STX
    INCHL
    LDA 0xF00007E7
    STX
    INCHL
    LDA 0xF00007E8
    STX
    INCHL
    LDA 0xF00007E9
    STX
    INCHL
    LDA 0xF00007EA
    STX
    INCHL
    LDA 0xF00007EB
    STX
    INCHL
    LDA 0xF00007EC
    STX
    INCHL
    LDA 0xF00007ED
    STX
    INCHL
    LDA 0xF00007EE
    STX
    INCHL
    LDA 0xF00007EF
    STX
    INCHL
    LDA 0xF00007F0
    STX
    INCHL
    LDA 0xF00007F1
    STX

    LDA dirDepth
    LDI B, 1
    ADD B
    STA dirDepth

cmd_cd_dir_done:

    ; copy_name_to_diskc и копирование в dirNames выше держали HL под
    ; свои нужды (адреса NAME/dirNames, не экран) - возвращаем HL на
    ; курсор экрана перед тем, как do_enter напечатает новый промпт
    ; (см. goto_row_start - тот же приём, что после dump/poke/exec).
    CALL goto_row_start

    RET


cmd_cd_dir_d:

    LDA dirDepth
    LDI B, 8
    CMP B
    JNC cmd_cd_dir_d_done

    LDI A, 3
    STA cn_prefix_len   ; длина префикса "cd "
    CALL find_name_and_arg_len
    CALL copy_name_to_diskd

    LDI A, 11
    STA 0xF0000805      ; DiskD COMMAND = CHDIR

    LDA 0xF0000806      ; DiskD STATUS
    LDI B, 0
    CMP B
    JNZ cmd_cd_dir_d_done

    LDHL dirNames
    LDA dirDepth
    LDI B, 12
    MUL B
    CALL hl_add_offset    ; HL = dirNames + dirDepth*12

    LDA 0xF00007F9
    STX
    INCHL
    LDA 0xF00007FA
    STX
    INCHL
    LDA 0xF00007FB
    STX
    INCHL
    LDA 0xF00007FC
    STX
    INCHL
    LDA 0xF00007FD
    STX
    INCHL
    LDA 0xF00007FE
    STX
    INCHL
    LDA 0xF00007FF
    STX
    INCHL
    LDA 0xF0000800
    STX
    INCHL
    LDA 0xF0000801
    STX
    INCHL
    LDA 0xF0000802
    STX
    INCHL
    LDA 0xF0000803
    STX
    INCHL
    LDA 0xF0000804
    STX

    LDA dirDepth
    LDI B, 1
    ADD B
    STA dirDepth

cmd_cd_dir_d_done:

    ; см. cmd_cd_dir_done - copy_name_to_diskd/dirNames держали HL под
    ; свои нужды, возвращаем на экран перед новым промптом
    CALL goto_row_start

    RET


cmd_exec:

    ; "exec ИМЯ" - собирает .asm-файл с текущего диска (currentDisk)
    ; и запускает его (LOAD в Disk - см. ASSEMBLY.md, "Disk").

    LDA currentDisk
    CMP D
    JNZ cmd_exec_d
    JMP cmd_exec_c


cmd_exec_c:

    LDI A, 5
    STA cn_prefix_len   ; длина префикса "exec "
    CALL find_name_and_arg_len

    LDA cn_name_len
    LDI B, 13
    CMP B
    JNC cmd_exec_done   ; имя длиннее 12 байт - не влезет в NAME, молча выходим

    CALL copy_name_to_diskc

    LDI A, 8
    STA 0xF00007F2      ; DiskC COMMAND = LOAD

    LDA 0xF00007F3      ; DiskC STATUS
    LDI B, 0
    CMP B
    JNZ cmd_exec_done   ; файл не найден/ошибка сборки - молча выходим

    JMP cmd_exec_run


cmd_exec_d:

    LDI A, 5
    STA cn_prefix_len   ; длина префикса "exec "
    CALL find_name_and_arg_len

    LDA cn_name_len
    LDI B, 13
    CMP B
    JNC cmd_exec_done   ; имя длиннее 12 байт - не влезет в NAME, молча выходим

    CALL copy_name_to_diskd

    LDI A, 8
    STA 0xF0000805      ; DiskD COMMAND = LOAD

    LDA 0xF0000806      ; DiskD STATUS
    LDI B, 0
    CMP B
    JNZ cmd_exec_done

    ; --- дошли сюда после успешной сборки - запускаем, как cmd_run ---

cmd_exec_run:

    ; Общая точка входа и для cmd_exec (exec ИМЯ [АРГУМЕНТ]), и для
    ; cmd_autorun (ИМЯ [АРГУМЕНТ]) - оба вызывали find_name_and_arg_len
    ; раньше в своей ветке, так что cn_arg_start/cn_arg_len уже готовы;
    ; copy_args_to_fixed переносит аргумент (или обнуляет канал, если
    ; его не было) в CMD_ARGS_LEN/CMD_ARGS_TEXT ДО запуска программы -
    ; см. ASSEMBLY.md, "Аргументы командной строки". cmd_run (голое
    ; "run", повторный запуск уже загруженного кода без разбора имени)
    ; сюда не заходит - у него нет cn_arg_len, канал он не трогает.

    CALL copy_args_to_fixed

    PUSH D          ; на случай, если программа испортит "константу 0"

    LDI A, 1
    STA 0x00010004        ; programRunning = 1 - Ctrl+Q во время работы
                          ; программы не должен гасить всю VM - см.
                          ; do_quit; main.cpp тоже читает этот адрес,
                          ; чтобы включать перерисовку по таймеру
                          ; только пока реально работает программа

    LDI A, 0
    STA 0x00010001        ; lastKey = 0 - свежий старт (см. cmd_run)

    CALL 0x00002000

    PUSH A                ; сохранить A программы на время сброса флага
    LDI A, 0
    STA 0x00010004        ; programRunning = 0
    POP A

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


cmd_create:

    ; "create ИМЯ" - создаёт пустой файл на currentDisk (OPEN_WRITE
    ; сразу создаёт/обрезает файл, CLOSE фиксирует - ничего писать
    ; в DATA не нужно для пустого файла).

    LDA currentDisk
    CMP D
    JNZ cmd_create_d
    JMP cmd_create_c


cmd_create_c:

    LDI A, 7
    STA cn_prefix_len   ; длина префикса "create "
    CALL find_name_and_arg_len
    CALL copy_name_to_diskc

    LDI A, 5
    STA 0xF00007F2      ; OPEN_WRITE
    LDI A, 7
    STA 0xF00007F2      ; CLOSE

    RET


cmd_create_d:

    LDI A, 7
    STA cn_prefix_len   ; длина префикса "create "
    CALL find_name_and_arg_len
    CALL copy_name_to_diskd

    LDI A, 5
    STA 0xF0000805
    LDI A, 7
    STA 0xF0000805

    RET


cmd_del:

    ; "del ИМЯ" - удаляет файл с currentDisk (DELETE = 9 в Disk)

    LDA currentDisk
    CMP D
    JNZ cmd_del_d
    JMP cmd_del_c


cmd_del_c:

    LDI A, 4
    STA cn_prefix_len   ; длина префикса "del "
    CALL find_name_and_arg_len
    CALL copy_name_to_diskc

    LDI A, 9
    STA 0xF00007F2      ; DELETE

    RET


cmd_del_d:

    LDI A, 4
    STA cn_prefix_len   ; длина префикса "del "
    CALL find_name_and_arg_len
    CALL copy_name_to_diskd

    LDI A, 9
    STA 0xF0000805

    RET


cmd_copy:

    ; "copy ИМЯ" - копирует файл с currentDisk на другой диск под тем
    ; же именем (побайтовый цикл через OPEN_READ/READ_BYTE на
    ; источнике и OPEN_WRITE/WRITE_BYTE на приёмнике - никакого HL,
    ; всё по фиксированным адресам, как в cmd_type).

    LDI A, 5
    STA cn_prefix_len   ; длина префикса "copy "
    CALL find_name_and_arg_len
    CALL copy_name_to_diskc

    LDI A, 5
    STA cn_prefix_len
    CALL copy_name_to_diskd

    LDA currentDisk
    CMP D
    JNZ cmd_copy_d_to_c
    JMP cmd_copy_c_to_d


cmd_copy_c_to_d:

    LDI A, 3
    STA 0xF00007F2      ; DiskC COMMAND = OPEN_READ

    LDA 0xF00007F3      ; DiskC STATUS
    LDI B, 2
    CMP B
    JZ cmd_copy_done    ; файл-источник не найден

    LDI A, 5
    STA 0xF0000805      ; DiskD COMMAND = OPEN_WRITE

cmd_copy_c_to_d_loop:

    LDI A, 4
    STA 0xF00007F2      ; DiskC COMMAND = READ_BYTE

    LDA 0xF00007F3      ; DiskC STATUS
    LDI B, 1
    CMP B
    JZ cmd_copy_c_to_d_close    ; EOF

    LDA 0xF00007F4      ; DiskC DATA
    STA 0xF0000807      ; DiskD DATA

    LDI A, 6
    STA 0xF0000805      ; DiskD COMMAND = WRITE_BYTE

    JMP cmd_copy_c_to_d_loop

cmd_copy_c_to_d_close:

    LDI A, 7
    STA 0xF00007F2      ; DiskC COMMAND = CLOSE
    LDI A, 7
    STA 0xF0000805      ; DiskD COMMAND = CLOSE

    JMP cmd_copy_done


cmd_copy_d_to_c:

    LDI A, 3
    STA 0xF0000805      ; DiskD COMMAND = OPEN_READ

    LDA 0xF0000806      ; DiskD STATUS
    LDI B, 2
    CMP B
    JZ cmd_copy_done

    LDI A, 5
    STA 0xF00007F2      ; DiskC COMMAND = OPEN_WRITE

cmd_copy_d_to_c_loop:

    LDI A, 4
    STA 0xF0000805      ; DiskD COMMAND = READ_BYTE

    LDA 0xF0000806      ; DiskD STATUS
    LDI B, 1
    CMP B
    JZ cmd_copy_d_to_c_close

    LDA 0xF0000807      ; DiskD DATA
    STA 0xF00007F4      ; DiskC DATA

    LDI A, 6
    STA 0xF00007F2      ; DiskC COMMAND = WRITE_BYTE

    JMP cmd_copy_d_to_c_loop

cmd_copy_d_to_c_close:

    LDI A, 7
    STA 0xF0000805      ; DiskD COMMAND = CLOSE
    LDI A, 7
    STA 0xF00007F2      ; DiskC COMMAND = CLOSE

cmd_copy_done:

    RET


cmd_build:

    ; "build ИМЯ.ASM" - собирает .asm в ИМЯ.RUN на currentDisk
    ; (BUILD = 14 в Disk) - готовый .RUN потом запускается напрямую
    ; по имени, без exec (см. cmd_autorun).

    LDA currentDisk
    CMP D
    JNZ cmd_build_d
    JMP cmd_build_c


cmd_build_c:

    LDI A, 6
    STA cn_prefix_len   ; длина префикса "build "
    CALL find_name_and_arg_len
    CALL copy_name_to_diskc

    LDI A, 14
    STA 0xF00007F2      ; DiskC COMMAND = BUILD

    RET


cmd_build_d:

    LDI A, 6
    STA cn_prefix_len   ; длина префикса "build "
    CALL find_name_and_arg_len
    CALL copy_name_to_diskd

    LDI A, 14
    STA 0xF0000805      ; DiskD COMMAND = BUILD

    RET


cmd_autorun:

    ; Последняя попытка распознать введённую строку: считаем её (или её
    ; часть до первого пробела - см. find_name_and_arg_len, ASSEMBLY.md,
    ; "Аргументы командной строки") именем программы, приписываем ".RUN"
    ; и пробуем запустить как готовый машинный код (LOAD_RAW = 13 в
    ; Disk) - так же, как в DOS печатают имя .exe без расширения (и, как
    ; в DOS, всё, что после первого пробела - аргумент, а не часть
    ; имени). Тихо ничего не делает, если получившееся имя не влезает в
    ; 12-байтовый NAME или файл не нашёлся - введённая строка в этом
    ; случае просто выглядит как неизвестная команда (как и раньше).

    LDA cmdlen
    LDI B, 1
    CMP B
    JC cmd_autorun_done   ; пустая строка (Enter без ввода) - нечего запускать

    LDI A, 0
    STA cn_prefix_len     ; нет префикса-команды - имя начинается с cmdbuf0
    CALL find_name_and_arg_len

    LDA cn_name_len
    LDI B, 9              ; cn_name_len+4 <= 12  =>  cn_name_len <= 8  =>  <9
    CMP B
    JNC cmd_autorun_done  ; слишком длинное имя - ИМЯ+".RUN" не влезет в NAME

    LDA currentDisk
    CMP D
    JNZ cmd_autorun_d
    JMP cmd_autorun_c


cmd_autorun_c:

    CALL copy_name_to_diskc
    CALL append_run_suffix_c

    LDI A, 13
    STA 0xF00007F2        ; DiskC COMMAND = LOAD_RAW

    LDA 0xF00007F3         ; DiskC STATUS
    LDI B, 0
    CMP B
    JNZ cmd_autorun_done   ; ИМЯ.RUN не нашёлся - молча выходим

    JMP cmd_exec_run       ; переиспользуем готовую логику запуска


cmd_autorun_d:

    CALL copy_name_to_diskd
    CALL append_run_suffix_d

    LDI A, 13
    STA 0xF0000805        ; DiskD COMMAND = LOAD_RAW

    LDA 0xF0000806
    LDI B, 0
    CMP B
    JNZ cmd_autorun_done

    JMP cmd_exec_run


cmd_autorun_done:

    RET


append_run_suffix_c:

    ; Дописывает ".RUN" в DiskC NAME сразу после уже скопированного
    ; имени (cn_name_len символов - см. find_name_and_arg_len; НЕ
    ; cmdlen, который теперь может включать ещё и аргумент через
    ; пробел). copy_name_to_diskc уже обнулил остаток NAME - здесь
    ; просто перезаписываем следующие 4 байта.

    LDHL 0xF00007E6       ; DiskC NAME0
    LDA cn_name_len
    CALL hl_add_offset    ; HL = NAME0 + cn_name_len

    LDI A, 46             ; '.'
    STX
    INCHL
    LDI A, 82             ; 'R'
    STX
    INCHL
    LDI A, 85             ; 'U'
    STX
    INCHL
    LDI A, 78             ; 'N'
    STX

    CALL goto_row_start   ; HL был занят под NAME - возвращаем на экран

    RET


append_run_suffix_d:

    LDHL 0xF00007F9       ; DiskD NAME0
    LDA cn_name_len
    CALL hl_add_offset

    LDI A, 46             ; '.'
    STX
    INCHL
    LDI A, 82             ; 'R'
    STX
    INCHL
    LDI A, 85             ; 'U'
    STX
    INCHL
    LDI A, 78             ; 'N'
    STX

    CALL goto_row_start

    RET


find_name_and_arg_len:

    ; Разбор "ИМЯ АРГУМЕНТ" (см. ASSEMBLY.md, "Аргументы командной
    ; строки") - ищет первый пробел (32) в cmdbuf начиная с cn_prefix_len
    ; (уже выставлен вызывающим кодом, как и раньше). Если нашла на
    ; позиции p: cn_name_len = p - cn_prefix_len, cn_arg_start = p + 1,
    ; cn_arg_len = cmdlen - cn_arg_start. Если не нашла (дошли до
    ; cmdlen): cn_name_len = cmdlen - cn_prefix_len (как раньше, без
    ; аргумента), cn_arg_len = 0. ДОЛЖНА вызываться ДО
    ; copy_name_to_diskc/d (который теперь читает cn_name_len, а не
    ; cmdlen напрямую).

    LDA cn_prefix_len
    STA fnl_i            ; i = prefix_len

fnl_loop:

    LDA fnl_i
    PUSH A
    POP B                ; B = i
    LDA cmdlen
    CMP B
    JZ fnl_no_space      ; i == cmdlen - дошли до конца, пробел не найден

    LDHL cmdbuf0
    LDA fnl_i
    CALL hl_add_offset   ; HL = cmdbuf0 + i
    LDX                  ; A = cmdbuf[i]

    LDI B, 32            ; ' '
    CMP B
    JZ fnl_found

    LDA fnl_i
    LDI B, 1
    ADD B
    STA fnl_i

    JMP fnl_loop

fnl_found:

    LDA cn_prefix_len
    PUSH A
    POP B
    LDA fnl_i             ; A = p
    SUB B                 ; A = p - prefix_len
    STA cn_name_len

    LDA fnl_i
    LDI B, 1
    ADD B                 ; A = p + 1
    STA cn_arg_start

    LDA cn_arg_start
    PUSH A
    POP B
    LDA cmdlen            ; A = cmdlen
    SUB B                 ; A = cmdlen - arg_start
    STA cn_arg_len

    CALL goto_row_start   ; HL был занят под cmdbuf - вернуть на экран

    RET

fnl_no_space:

    LDA cn_prefix_len
    PUSH A
    POP B
    LDA cmdlen
    SUB B
    STA cn_name_len

    LDI A, 0
    STA cn_arg_len

    CALL goto_row_start   ; HL мог быть занят под cmdbuf - вернуть на экран

    RET


copy_args_to_fixed:

    ; Копирует cn_arg_len байт из cmdbuf[cn_arg_start..] в CMD_ARGS_TEXT
    ; (0x00010006..0x00010015, ARGS_MAX=16 - см. ASSEMBLY.md, "Аргументы
    ; командной строки"), дозаполняет нулями до 16 байт, пишет итоговую
    ; длину в CMD_ARGS_LEN (0x00010005). Тот же приём, что
    ; copy_name_to_diskc, но адресат - фиксированный адрес, а не
    ; NAME-регистр устройства. Клэмпит cn_arg_len до 16, если строка
    ; ввода была длиннее (защита от переполнения буфера назначения -
    ; чтение из cmdbuf сверх реально введённого тихо даёт нулевые байты).
    ; Вызывается ВСЕГДА (даже с cn_arg_len=0) - обнуляет канал для
    ; программ без аргументов, как и lastKey перед CALL 0x00002000.

    LDA cn_arg_len
    LDI B, 16
    CMP B
    JC cafx_len_ok        ; cn_arg_len < 16 - используем как есть
    LDI A, 16
    STA cn_arg_len         ; клэмп до ARGS_MAX

cafx_len_ok:

    LDA cn_arg_len
    STA 0x00010005         ; CMD_ARGS_LEN

    LDI A, 0
    STA ca_i

cafx_loop:

    LDA ca_i
    PUSH A
    POP B
    LDA cn_arg_len
    CMP B
    JZ cafx_pad           ; i == cn_arg_len - копирование окончено

    LDHL cmdbuf0
    LDA cn_arg_start
    PUSH A
    POP B
    LDA ca_i
    ADD B                 ; A = arg_start + i
    CALL hl_add_offset    ; HL = cmdbuf0 + arg_start + i

    LDX
    STA ca_char

    LDHL 0x00010006       ; CMD_ARGS_TEXT
    LDA ca_i
    CALL hl_add_offset    ; HL = CMD_ARGS_TEXT + i

    LDA ca_char
    STX

    LDA ca_i
    LDI B, 1
    ADD B
    STA ca_i

    JMP cafx_loop

cafx_pad:

    LDA ca_i
    LDI B, 16
    CMP B
    JZ cafx_done          ; i == 16 - весь остаток обнулён

    LDHL 0x00010006
    LDA ca_i
    CALL hl_add_offset

    LDI A, 0
    STX

    LDA ca_i
    LDI B, 1
    ADD B
    STA ca_i

    JMP cafx_pad

cafx_done:

    CALL goto_row_start   ; HL был занят - вернуть на экранный курсор

    RET


copy_name_to_diskc:

    ; Копирует cmdbuf[prefix_len]..cmdbuf[prefix_len+len-1] в DiskC
    ; NAME0..NAME(len-1) и обнуляет остаток NAME(len)..NAME11.
    ; prefix_len - длина префикса команды ("type "=5, "create "=7,
    ; "del "=4, "copy "=5 и т.д.) - вызывающий код обязан положить её
    ; в cn_prefix_len ДО этого CALL. len = cmdlen - prefix_len (в
    ; tmp1). cmdbuf0 и NAME0 - оба физически непрерывные блоки в
    ; памяти (cmdbuf0..11 - последовательные DB, NAME0..11 -
    ; последовательные MMIO-регистры), поэтому используем
    ; hl_add_offset дважды на байт - один раз для чтения (HL на
    ; cmdbuf), один раз для записи (HL на NAME) - HL держит только
    ; один адрес одновременно. len берётся из cn_name_len - его должен
    ; заранее посчитать find_name_and_arg_len (см. выше), которая
    ; отделяет имя файла от необязательного аргумента по первому
    ; пробелу - CALL copy_name_to_diskc/d без предварительного CALL
    ; find_name_and_arg_len даст мусор в cn_name_len.

    LDA cn_name_len
    STA tmp1            ; tmp1 = len

    LDI A, 0
    STA tmp2            ; tmp2 = i

cnc_loop:

    LDA tmp1
    PUSH A
    POP B               ; B = len

    LDA tmp2
    CMP B
    JZ cnc_pad          ; i == len -> копирование окончено

    LDHL cmdbuf0
    LDA cn_prefix_len
    PUSH A
    POP B
    LDA tmp2
    ADD B               ; A = prefix_len + i
    CALL hl_add_offset  ; HL = cmdbuf0 + prefix_len + i

    LDX
    STA cn_char

    LDHL 0xF00007E6     ; DiskC NAME0
    LDA tmp2
    CALL hl_add_offset  ; HL = NAME0 + i

    LDA cn_char
    STX

    LDA tmp2
    LDI B, 1
    ADD B
    STA tmp2

    JMP cnc_loop

cnc_pad:

    LDA tmp2
    LDI B, 12
    CMP B
    JZ cnc_done         ; i == 12 -> весь остаток обнулён

    LDHL 0xF00007E6
    LDA tmp2
    CALL hl_add_offset

    LDI A, 0
    STX

    LDA tmp2
    LDI B, 1
    ADD B
    STA tmp2

    JMP cnc_pad

cnc_done:

    CALL goto_row_start   ; HL всё это время был занят под NAME -
                           ; возвращаем его на экранный курсор

    RET


copy_name_to_diskd:

    ; То же самое, но диск D: NAME0 = 0xF00007F9. См. copy_name_to_diskc
    ; про cn_prefix_len/cn_name_len.

    LDA cn_name_len
    STA tmp1

    LDI A, 0
    STA tmp2

cnd_loop:

    LDA tmp1
    PUSH A
    POP B

    LDA tmp2
    CMP B
    JZ cnd_pad

    LDHL cmdbuf0
    LDA cn_prefix_len
    PUSH A
    POP B
    LDA tmp2
    ADD B
    CALL hl_add_offset

    LDX
    STA cn_char

    LDHL 0xF00007F9     ; DiskD NAME0
    LDA tmp2
    CALL hl_add_offset

    LDA cn_char
    STX

    LDA tmp2
    LDI B, 1
    ADD B
    STA tmp2

    JMP cnd_loop

cnd_pad:

    LDA tmp2
    LDI B, 12
    CMP B
    JZ cnd_done

    LDHL 0xF00007F9
    LDA tmp2
    CALL hl_add_offset

    LDI A, 0
    STX

    LDA tmp2
    LDI B, 1
    ADD B
    STA tmp2

    JMP cnd_pad

cnd_done:

    CALL goto_row_start   ; см. cnc_done

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
; keyCount/lastKey/bannerReady/doneReady/programRunning
; (0x00010000-0x00010004) сюда не входят: их напрямую читает main.cpp,
; который не видит меток ассемблера, поэтому они остаются
; фиксированными адресами - это осознанный интерфейс хост-VM, а не
; магический адрес наугад. programRunning (0x00010004, "1" - пока
; внутри CALL 0x00002000 у exec/run, см. do_quit/cmd_run/cmd_exec_run)
; main.cpp использует, чтобы включать перерисовку экрана по таймеру
; только пока реально работает программа, а не постоянно.
;
; CMD_ARGS_LEN (0x00010005) и CMD_ARGS_TEXT (0x00010006-0x00010015, 16
; байт) - по той же причине фиксированные адреса, но интерфейс не с
; main.cpp, а с ЗАПУЩЕННОЙ программой (см. copy_args_to_fixed выше,
; ASSEMBLY.md "Аргументы командной строки") - канал, которым shell
; передаёт запущенной программе текст после имени файла ("exec ИМЯ
; АРГУМЕНТ", автозапуск "ИМЯ АРГУМЕНТ"), а любая уже выполняющаяся
; программа - своей дочерней через exec_child() (сама кладёт значения
; сюда перед CALL, канал в этом случае НЕ обнуляется автоматически - как
; и EXEC_CHILD_DISK, 0x0000000F). Доступны из Мини-C как CMD_ARGS_LEN/
; cmdArgs[16] (см. прелюдию устройств, Compiler.cpp).
; ============================================================

quit:       DB 0
column:     DB 0
row:        DB 0
cmdlen:     DB 0
lastChar:   DB 0
currentDisk: DB 0   ; 0 = диск C, 1 = диск D (см. cmd_cd)

; Глубина вложенности exec_child() (см. shell_exec_child) - 1, пока
; выполняется только обычная программа "shell -> X" (exec/run/
; autorun), увеличивается на время CALL во вложенный уровень.
execDepth:    DB 1
sec_cmdValue: DB 0   ; scratch - номер команды диска, выбранной в shell_exec_child

; Стек имён папок для промпта (произвольная вложенность, не только
; один уровень - см. cmd_cd_dir*/cmd_cd_up/print_prompt). Disk сам по
; себе (Disk::currentDir - std::filesystem::path) уже поддерживал
; любую глубину с самого начала - ограничены были только шелл и его
; промпт, хранившие "текущую папку" как один булев флаг + одно имя.
; DIR_MAX_DEPTH = 8 - памяти много (4 МБ RAM), 96 байт под это не
; жалко.
dirDepth: DB 0      ; 0..8 - текущая глубина вложенности
dirNames: DB 0      ; 8 * 12 байт подряд - имя каждого уровня (формат
          DB 0      ; 8.3, как NAME) - уровень N занимает [N*12..N*12+11]
          DB 0      ; 8.3, как NAME) - уровень N занимает [N*12..N*12+11]
          DB 0      ; 8.3, как NAME) - уровень N занимает [N*12..N*12+11]
          DB 0      ; 8.3, как NAME) - уровень N занимает [N*12..N*12+11]
          DB 0      ; 8.3, как NAME) - уровень N занимает [N*12..N*12+11]
          DB 0      ; 8.3, как NAME) - уровень N занимает [N*12..N*12+11]
          DB 0      ; 8.3, как NAME) - уровень N занимает [N*12..N*12+11]
          DB 0      ; 8.3, как NAME) - уровень N занимает [N*12..N*12+11]
          DB 0      ; 8.3, как NAME) - уровень N занимает [N*12..N*12+11]
          DB 0      ; 8.3, как NAME) - уровень N занимает [N*12..N*12+11]
          DB 0      ; 8.3, как NAME) - уровень N занимает [N*12..N*12+11]
          DB 0      ; 8.3, как NAME) - уровень N занимает [N*12..N*12+11]
          DB 0      ; 8.3, как NAME) - уровень N занимает [N*12..N*12+11]
          DB 0      ; 8.3, как NAME) - уровень N занимает [N*12..N*12+11]
          DB 0      ; 8.3, как NAME) - уровень N занимает [N*12..N*12+11]
          DB 0      ; 8.3, как NAME) - уровень N занимает [N*12..N*12+11]
          DB 0      ; 8.3, как NAME) - уровень N занимает [N*12..N*12+11]
          DB 0      ; 8.3, как NAME) - уровень N занимает [N*12..N*12+11]
          DB 0      ; 8.3, как NAME) - уровень N занимает [N*12..N*12+11]
          DB 0      ; 8.3, как NAME) - уровень N занимает [N*12..N*12+11]
          DB 0      ; 8.3, как NAME) - уровень N занимает [N*12..N*12+11]
          DB 0      ; 8.3, как NAME) - уровень N занимает [N*12..N*12+11]
          DB 0      ; 8.3, как NAME) - уровень N занимает [N*12..N*12+11]
          DB 0      ; 8.3, как NAME) - уровень N занимает [N*12..N*12+11]
          DB 0      ; 8.3, как NAME) - уровень N занимает [N*12..N*12+11]
          DB 0      ; 8.3, как NAME) - уровень N занимает [N*12..N*12+11]
          DB 0      ; 8.3, как NAME) - уровень N занимает [N*12..N*12+11]
          DB 0      ; 8.3, как NAME) - уровень N занимает [N*12..N*12+11]
          DB 0      ; 8.3, как NAME) - уровень N занимает [N*12..N*12+11]
          DB 0      ; 8.3, как NAME) - уровень N занимает [N*12..N*12+11]
          DB 0      ; 8.3, как NAME) - уровень N занимает [N*12..N*12+11]
          DB 0      ; 8.3, как NAME) - уровень N занимает [N*12..N*12+11]
          DB 0      ; 8.3, как NAME) - уровень N занимает [N*12..N*12+11]
          DB 0      ; 8.3, как NAME) - уровень N занимает [N*12..N*12+11]
          DB 0      ; 8.3, как NAME) - уровень N занимает [N*12..N*12+11]
          DB 0      ; 8.3, как NAME) - уровень N занимает [N*12..N*12+11]
          DB 0      ; 8.3, как NAME) - уровень N занимает [N*12..N*12+11]
          DB 0      ; 8.3, как NAME) - уровень N занимает [N*12..N*12+11]
          DB 0      ; 8.3, как NAME) - уровень N занимает [N*12..N*12+11]
          DB 0      ; 8.3, как NAME) - уровень N занимает [N*12..N*12+11]
          DB 0      ; 8.3, как NAME) - уровень N занимает [N*12..N*12+11]
          DB 0      ; 8.3, как NAME) - уровень N занимает [N*12..N*12+11]
          DB 0      ; 8.3, как NAME) - уровень N занимает [N*12..N*12+11]
          DB 0      ; 8.3, как NAME) - уровень N занимает [N*12..N*12+11]
          DB 0      ; 8.3, как NAME) - уровень N занимает [N*12..N*12+11]
          DB 0      ; 8.3, как NAME) - уровень N занимает [N*12..N*12+11]
          DB 0      ; 8.3, как NAME) - уровень N занимает [N*12..N*12+11]
          DB 0      ; 8.3, как NAME) - уровень N занимает [N*12..N*12+11]
          DB 0      ; 8.3, как NAME) - уровень N занимает [N*12..N*12+11]
          DB 0      ; 8.3, как NAME) - уровень N занимает [N*12..N*12+11]
          DB 0      ; 8.3, как NAME) - уровень N занимает [N*12..N*12+11]
          DB 0      ; 8.3, как NAME) - уровень N занимает [N*12..N*12+11]
          DB 0      ; 8.3, как NAME) - уровень N занимает [N*12..N*12+11]
          DB 0      ; 8.3, как NAME) - уровень N занимает [N*12..N*12+11]
          DB 0      ; 8.3, как NAME) - уровень N занимает [N*12..N*12+11]
          DB 0      ; 8.3, как NAME) - уровень N занимает [N*12..N*12+11]
          DB 0      ; 8.3, как NAME) - уровень N занимает [N*12..N*12+11]
          DB 0      ; 8.3, как NAME) - уровень N занимает [N*12..N*12+11]
          DB 0      ; 8.3, как NAME) - уровень N занимает [N*12..N*12+11]
          DB 0      ; 8.3, как NAME) - уровень N занимает [N*12..N*12+11]
          DB 0      ; 8.3, как NAME) - уровень N занимает [N*12..N*12+11]
          DB 0      ; 8.3, как NAME) - уровень N занимает [N*12..N*12+11]
          DB 0      ; 8.3, как NAME) - уровень N занимает [N*12..N*12+11]
          DB 0      ; 8.3, как NAME) - уровень N занимает [N*12..N*12+11]
          DB 0      ; 8.3, как NAME) - уровень N занимает [N*12..N*12+11]
          DB 0      ; 8.3, как NAME) - уровень N занимает [N*12..N*12+11]
          DB 0      ; 8.3, как NAME) - уровень N занимает [N*12..N*12+11]
          DB 0      ; 8.3, как NAME) - уровень N занимает [N*12..N*12+11]
          DB 0      ; 8.3, как NAME) - уровень N занимает [N*12..N*12+11]
          DB 0      ; 8.3, как NAME) - уровень N занимает [N*12..N*12+11]
          DB 0      ; 8.3, как NAME) - уровень N занимает [N*12..N*12+11]
          DB 0      ; 8.3, как NAME) - уровень N занимает [N*12..N*12+11]
          DB 0      ; 8.3, как NAME) - уровень N занимает [N*12..N*12+11]
          DB 0      ; 8.3, как NAME) - уровень N занимает [N*12..N*12+11]
          DB 0      ; 8.3, как NAME) - уровень N занимает [N*12..N*12+11]
          DB 0      ; 8.3, как NAME) - уровень N занимает [N*12..N*12+11]
          DB 0      ; 8.3, как NAME) - уровень N занимает [N*12..N*12+11]
          DB 0      ; 8.3, как NAME) - уровень N занимает [N*12..N*12+11]
          DB 0      ; 8.3, как NAME) - уровень N занимает [N*12..N*12+11]
          DB 0      ; 8.3, как NAME) - уровень N занимает [N*12..N*12+11]
          DB 0      ; 8.3, как NAME) - уровень N занимает [N*12..N*12+11]
          DB 0      ; 8.3, как NAME) - уровень N занимает [N*12..N*12+11]
          DB 0      ; 8.3, как NAME) - уровень N занимает [N*12..N*12+11]
          DB 0      ; 8.3, как NAME) - уровень N занимает [N*12..N*12+11]
          DB 0      ; 8.3, как NAME) - уровень N занимает [N*12..N*12+11]
          DB 0      ; 8.3, как NAME) - уровень N занимает [N*12..N*12+11]
          DB 0      ; 8.3, как NAME) - уровень N занимает [N*12..N*12+11]
          DB 0      ; 8.3, как NAME) - уровень N занимает [N*12..N*12+11]
          DB 0      ; 8.3, как NAME) - уровень N занимает [N*12..N*12+11]
          DB 0      ; 8.3, как NAME) - уровень N занимает [N*12..N*12+11]
          DB 0      ; 8.3, как NAME) - уровень N занимает [N*12..N*12+11]
          DB 0      ; 8.3, как NAME) - уровень N занимает [N*12..N*12+11]
          DB 0      ; 8.3, как NAME) - уровень N занимает [N*12..N*12+11]
          DB 0      ; 8.3, как NAME) - уровень N занимает [N*12..N*12+11]
          DB 0      ; 8.3, как NAME) - уровень N занимает [N*12..N*12+11]

; временные для print_prompt (печать имён из dirNames - см. ниже про
; конфликт HL между "курсор экрана" и "чтение dirNames")
ppLevel: DB 0   ; текущий уровень 0..dirDepth-1
ppChar:  DB 0   ; текущий символ внутри имени уровня, 0..11
ppByte:  DB 0   ; прочитанный из dirNames символ, ждёт печати

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

cn_char:    DB 0   ; байт имени файла на время переноса cmdbuf->NAME
                    ; (copy_name_to_diskc/d)

cn_prefix_len: DB 0 ; длина префикса команды перед именем файла -
                    ; вызывающий код обязан установить перед CALL
                    ; copy_name_to_diskc/d (5 для type/exec/copy,
                    ; 7 для create, 4 для del)

; Разбор "ИМЯ АРГУМЕНТ" (см. find_name_and_arg_len, ASSEMBLY.md,
; "Аргументы командной строки") - вызывающий код (cmd_exec/cmd_autorun)
; выставляет cn_prefix_len и зовёт find_name_and_arg_len ДО
; copy_name_to_diskc/d (который теперь читает cn_name_len вместо того,
; чтобы пересчитывать его из cmdlen самостоятельно).
fnl_i:         DB 0   ; scratch - текущая позиция поиска пробела
cn_name_len:   DB 0   ; длина имени файла (до пробела или до конца строки)
cn_arg_start:  DB 0   ; позиция в cmdbuf, откуда начинается аргумент (после пробела)
cn_arg_len:    DB 0   ; длина аргумента (0 - аргумента нет)
ca_i:          DB 0   ; scratch - индекс копирования в copy_args_to_fixed
ca_char:       DB 0   ; scratch - байт аргумента на время переноса cmdbuf->CMD_ARGS_TEXT

; Буфер команды - 36 отдельных байт (0..35), не единый массив (см.
; комментарий в do_echo). Изначально был 12 байт (под "poke NNN VVV"),
; затем 20 (под "create ИМЯ.ЕХТ" = 19 символов); расширен до 36, чтобы
; влезло "exec "(5) + имя(12) + " "(1) + аргумент(16, см. CMD_ARGS_TEXT)
; = 34, с небольшим запасом - см. ASSEMBLY.md, "Аргументы командной
; строки".

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
cmdbuf12:   DB 0
cmdbuf13:   DB 0
cmdbuf14:   DB 0
cmdbuf15:   DB 0
cmdbuf16:   DB 0
cmdbuf17:   DB 0
cmdbuf18:   DB 0
cmdbuf19:   DB 0
cmdbuf20:   DB 0
cmdbuf21:   DB 0
cmdbuf22:   DB 0
cmdbuf23:   DB 0
cmdbuf24:   DB 0
cmdbuf25:   DB 0
cmdbuf26:   DB 0
cmdbuf27:   DB 0
cmdbuf28:   DB 0
cmdbuf29:   DB 0
cmdbuf30:   DB 0
cmdbuf31:   DB 0
cmdbuf32:   DB 0
cmdbuf33:   DB 0
cmdbuf34:   DB 0
cmdbuf35:   DB 0
