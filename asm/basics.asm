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
set a, x
set b, y
jsr emit
add x, 1
sub y, 1
ifg y, 0
  set pc, emit_string_loop

set y, pop
set x, pop
set pc, pop



:test_string
DAT "Hello, DCPU!"

:main
set a, test_string
set b, 12
jsr emit_string
set a, 10
jsr emit

hcf 0
