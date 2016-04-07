; Math ops testing code for my DCPU-16 interpreter.

set pc, main

; First, some library functions.

:emit ; A = character to emit
set b, a
set a, 2
hwi 0
set pc, pop

:hex_table
DAT "0123456789ABCDEF"

:emit_number ; A = a number to output in hex.
set push, x
set x, a
set b, a

set a, 2

shr b, 12
and b, 15
set b, [b+hex_table]
hwi 0

set b, x
shr b, 8
and b, 15
set b, [b+hex_table]
set a, 2
hwi 0

set b, x
shr b, 4
and b, 15
set b, [b+hex_table]
set a, 2
hwi 0

set b, x
and b, 15
set b, [b+hex_table]
set a, 2
hwi 0

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




:str_test_failed_1
DAT "Test #", 0
:str_test_failed_2
DAT " failed. Expected ", 0
:str_test_failed_3
DAT " but got ", 0

; The main testing function: A and B are the inputs, X the function to call, Y
; the expected value in A after the call, Z the test number, I the expected EX
; Silent on success, emits an error when there's a problem.
:math_test
jsr x
; Now compare A with Y, the actual and expected results
ife a, y
  ife ex, i
    set pc, math_test_good

; Bad! There's a mismatch, so we emit an error message.
set push, ex ; Save the EX
set push, a ; And the old result.
set a, str_test_failed_1
jsr emit_cstring
set a, z
jsr emit_number

set a, str_test_failed_2
jsr emit_cstring
set a, y
jsr emit_number

set a, str_test_failed_3
jsr emit_cstring

set a, pop
jsr emit_number

set a, 32
jsr emit
set a, i
jsr emit_number ; Expected EX
set a, 32
jsr emit
set a, pop
jsr emit_number ; Actual EX

set a, 10
jsr emit

hcf z


:math_test_good
set pc, pop




; And the battery of tests
:test_add
add a, b
set pc, pop
:test_sub
sub a, b
set pc, pop
:test_mul
mul a, b
set pc, pop
:test_mli
mli a, b
set pc, pop
:test_div
div a, b
set pc, pop
:test_dvi
dvi a, b
set pc, pop
:test_mod
mod a, b
set pc, pop
:test_mdi
mdi a, b
set pc, pop
:test_shr
shr a, b
set pc, pop
:test_shl
shl a, b
set pc, pop
:test_asr
asr a, b
set pc, pop

; These are: function, A, B, expected result, expected EX
:tests
DAT test_add, 0, 0, 0, 0
DAT test_add, 1, 1, 2, 0
DAT test_add, 0, 1, 1, 0
DAT test_add, -1, 1, 0, 1
DAT test_add, -1, -1, -2, 1

; #5
DAT test_sub, 8, 8, 0, 0
DAT test_sub, 8, 6, 2, 0
DAT test_sub, 5, 6, -1, -1
DAT test_sub, 0, 0, 0, 0
DAT test_sub, 0, 1, -1, -1
DAT test_sub, -1, -1, 0, 0

; #b
DAT test_mul, 8, 8, 64, 0
DAT test_mul, 7, 3, 21, 0
DAT test_mul, 1, -1, -1, 0
DAT test_mul, 2, -1, -2, 1
DAT test_mul, -7, -4, 0x001c, 0xfff5

; #10
DAT test_mli, 8, 8, 64, 0
DAT test_mli, 7, 3, 21, 0
DAT test_mli, 1, -1, -1, -1
DAT test_mli, 2, -1, -2, -1
DAT test_mli, -7, -4, 28, 0

; #15
DAT test_div, 21, 0, 0, 0
DAT test_div, 21, 3, 7, 0
DAT test_div, 21, 7, 3, 0
DAT test_div, 24, 7, 3, 0x6db6 ; 24 << 16 is 0x180000 and 0x180000 / 7 = 0x36db6
DAT test_div, 24, -7, 0, 24

; #1a
DAT test_dvi, 21, 0, 0, 0
DAT test_dvi, 21, 3, 7, 0
DAT test_dvi, 21, 7, 3, 0
DAT test_dvi, 24, 7, 3, 0x6db6 ; This and the next three are confirmed with
                               ; other emulators.
DAT test_dvi, -24, 7, -3, 0x924a
DAT test_dvi, 24, -7, -3, 0x924a
DAT test_dvi, -24, -7, 3, 0x6db6

; #21
DAT test_mod, 21, 0, 0, 0
DAT test_mod, 21, 3, 0, 0
DAT test_mod, 21, 7, 0, 0
DAT test_mod, 24, 7, 3, 0
DAT test_mod, 24, -7, 24, 0

; #26
DAT test_mdi, 21, 0, 0, 0
DAT test_mdi, 21, 3, 0, 0
DAT test_mdi, 21, 7, 0, 0
DAT test_mdi, 24, 7, 3, 0
DAT test_mdi, -24, 7, -3, 0
DAT test_mdi, 24, -7, 3, 0
DAT test_mdi, -24, -7, -3, 0

; #2d
DAT test_shr, 0, 0, 0, 0
DAT test_shr, 1, 1, 0, 0x8000
DAT test_shr, 3, 1, 1, 0x8000
DAT test_shr, 64, 3, 8, 0
DAT test_shr, -1, 3, 0x1fff, 0xe000

; #32
DAT test_shl, 0, 0, 0, 0
DAT test_shl, 1, 1, 2, 0
DAT test_shl, 0x0074, 3, 0x03a0, 0
DAT test_shl, 64, 3, 512, 0
DAT test_shl, -1, 3, 0xfff8, 7

; #37
DAT test_asr, 0, 0, 0, 0
DAT test_asr, 1, 1, 0, 0x8000
DAT test_asr, 3, 1, 1, 0x8000
DAT test_asr, 64, 3, 8, 0
DAT test_asr, -1, 3, 0xffff, 0xe000
DAT test_asr, -64, 3, -8, 0
:tests_top


:main
set push, 0

:test_loop
set i, pop
set z, i
add i, 1
set push, i

set i, z
mul i, 5
add i, tests

ife i, tests_top
  hcf 0

set x, [i] ; The function to call.
set a, [i+1] ; The LHS argument
set b, [i+2] ; The RHS argument
set y, [i+3] ; The expected result
set i, [i+4] ; Expected EX
jsr math_test
set pc, test_loop

