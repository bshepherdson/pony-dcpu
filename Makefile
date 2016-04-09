.PHONY: all

OS_FILES=asm/head.dasm asm/screen.dasm asm/main.dasm asm/boot.dasm

default: all

os: $(OS_FILES)
	cat $(OS_FILES) > __temp.dasm
	das -o test.bin __temp.dasm -d --dumpfile test.dump
	rm __temp.dasm

all: os

clean:
	rm test.bin

