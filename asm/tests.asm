; Test suite for my DCPU-16 interpreter.
; Assumes the serial console hardware is #0.

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




:str_math_test_failed_1
DAT "Math Test #", 0
:str_branch_test_failed_1
DAT "Branch Test #", 0
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
set a, str_math_test_failed_1
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




; Math test helper functions
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

; Math test specs
; These are: function, A, B, expected result, expected EX
:math_tests
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
:math_tests_top


:math_test_suite
set push, 0

:math_test_loop
set i, pop
set z, i
add i, 1
set push, i

set i, z
mul i, 5
add i, math_tests

ife i, math_tests_top
  set pc, math_test_suite_done

set x, [i] ; The function to call.
set a, [i+1] ; The LHS argument
set b, [i+2] ; The RHS argument
set y, [i+3] ; The expected result
set i, [i+4] ; Expected EX
jsr math_test
set pc, math_test_loop

:math_test_suite_done
set i, pop
set pc, pop




;==========================================================================
; Branch tests
;==========================================================================

; Most of these have the same format: set c to 0, set it to 1 in the branch.
:test_ifb
set c, 0
ifb a, b
  set c, 1
set pc, pop
:test_ifc
set c, 0
ifc a, b
  set c, 1
set pc, pop
:test_ife
set c, 0
ife a, b
  set c, 1
set pc, pop
:test_ifn
set c, 0
ifn a, b
  set c, 1
set pc, pop
:test_ifg
set c, 0
ifg a, b
  set c, 1
set pc, pop
:test_ifa
set c, 0
ifa a, b
  set c, 1
set pc, pop
:test_ifl
set c, 0
ifl a, b
  set c, 1
set pc, pop
:test_ifu
set c, 0
ifu a, b
  set c, 1
set pc, pop

; Slightly different. Check 7 < A < 41, ignore B.
:test_if_skip
set c, 0
ifl 7, a
  ifl a, 41
    set c, 1
set pc, pop


; These have the format: function, a, b, expected c
:branch_tests
DAT test_ifb, 0, 0, 0
DAT test_ifb, 5, 2, 0
DAT test_ifb, 5, 3, 1
DAT test_ifb, 3, 3, 1

; #04
DAT test_ifc, 0, 0, 1
DAT test_ifc, 5, 2, 1
DAT test_ifc, 5, 3, 0
DAT test_ifc, 3, 3, 0

; #08
DAT test_ife, 0, 0, 1
DAT test_ife, 5, 2, 0
DAT test_ife, 5, 3, 0
DAT test_ife, 3, 3, 1
DAT test_ife, -51, -51, 1
DAT test_ife, -51, -48, 0

; #0e
DAT test_ifn, 0, 0, 0
DAT test_ifn, 5, 2, 1
DAT test_ifn, 5, 3, 1
DAT test_ifn, 3, 3, 0
DAT test_ifn, -51, -51, 0
DAT test_ifn, -51, -48, 1

; #14
DAT test_ifg, 0, 0, 0
DAT test_ifg, 0, 1, 0
DAT test_ifg, 1, 0, 1
DAT test_ifg, 71, 45, 1
DAT test_ifg, 71, 85, 0
DAT test_ifg, -1, 0, 1
DAT test_ifg, -1, -4, 1
DAT test_ifg, -1, 1, 1
DAT test_ifg, 1, -1, 0

; #1d
DAT test_ifa, 0, 0, 0
DAT test_ifa, 0, 1, 0
DAT test_ifa, 1, 0, 1
DAT test_ifa, 71, 45, 1
DAT test_ifa, 71, 85, 0
DAT test_ifa, -1, 0, 0
DAT test_ifa, -1, -4, 1
DAT test_ifa, -4, -1, 0
DAT test_ifa, -1, 1, 0
DAT test_ifa, 1, -1, 1

; #27
DAT test_ifl, 0, 0, 0
DAT test_ifl, 0, 1, 1
DAT test_ifl, 1, 0, 0
DAT test_ifl, 71, 45, 0
DAT test_ifl, 71, 85, 1
DAT test_ifl, -1, 0, 0
DAT test_ifl, -1, -4, 0
DAT test_ifl, -1, 1, 0
DAT test_ifl, 1, -1, 1

; #30
DAT test_ifu, 0, 0, 0
DAT test_ifu, 0, 1, 1
DAT test_ifu, 1, 0, 0
DAT test_ifu, 71, 45, 0
DAT test_ifu, 71, 85, 1
DAT test_ifu, -1, 0, 1
DAT test_ifu, -1, -4, 0
DAT test_ifu, -4, -1, 1
DAT test_ifu, -1, 1, 1
DAT test_ifu, 1, -1, 0

; #3a - these check if A is 7 < a < 41, and ignore B.
DAT test_if_skip, 2, 0, 0
DAT test_if_skip, 7, 0, 0
DAT test_if_skip, 8, 0, 1
DAT test_if_skip, 22, 0, 1
DAT test_if_skip, 40, 0, 1
DAT test_if_skip, 41, 0, 0
DAT test_if_skip, 61, 0, 0

:branch_tests_top


; The main testing function: A and B are the inputs, X the function to call, Y
; the expected value in A after the call, Z the test number.
; Silent on success, emits an error when there's a problem.
:branch_test
jsr x
; Now compare C with Y, the actual and expected results
ife c, y
  set pc, branch_test_good

; Bad! There's a mismatch, so we emit an error message.
set push, c ; Save the old result.
set a, str_branch_test_failed_1
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

set a, 10
jsr emit

hcf z

:branch_test_good
set pc, pop



:branch_test_suite
set push, 0

:branch_test_loop
set i, pop
set z, i
add i, 1
set push, i

set i, z
mul i, 4
add i, branch_tests

ife i, branch_tests_top
  set pc, branch_test_suite_done

set x, [i] ; The function to call.
set a, [i+1] ; The LHS argument
set b, [i+2] ; The RHS argument
set y, [i+3] ; The expected result
jsr branch_test
set pc, branch_test_loop

:branch_test_suite_done
set i, pop
set pc, pop



:main
jsr math_test_suite
jsr branch_test_suite
hcf 0

