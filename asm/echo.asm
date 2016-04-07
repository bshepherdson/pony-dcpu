; Echoes back serial console input.

.equ hw_serial, 0

ias handler
iaq 0

set a, 0
set b, 1 ; B is the message number for the serial port.
hwi hw_serial

sub pc, 1

:handler
set push, b
set a, 1
hwi hw_serial ; B is now the next character.

set a, 2
hwi hw_serial ; Echo it back.
set b, pop
rfi 0





