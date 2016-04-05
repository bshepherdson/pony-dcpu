; Basic test code for my DCPU-16 interpreter.
; Writes A\n to the serial link.

set pc, main

:emit ; A = character to emit
set b, a
set a, 2
hwi 0
set pc, pop

:emit_string ; A = address of character array, B = length
set push, x
set push, y
set x, a
set y, b
:emit_string_loop
set a, [x]
jsr emit
add x, 1
sub y, 1
ifg y, 0
  set pc, emit_string_loop

set y, pop
set x, pop
set pc, pop


:emit_cstring ; A = address C-style null-terminated string
set push, x
set x, a
:emit_cstring_loop
set a, [x]
ife a, 0
  set pc, emit_cstring_done
jsr emit
add x, 1
set pc, emit_cstring_loop

:emit_cstring_done
set x, pop
set pc, pop


:test_string
DAT "Hello, DCPU!", 0

:main
set a, test_string
jsr emit_cstring
set a, 10
jsr emit

hcf 0
