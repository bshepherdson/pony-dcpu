// A hacky, console version of the LEM 1802 display.
// It renders in the terminal by mapping the DCPU characters to Unicode and
// ASCII characters.

use ".."
use "signals"
use "time"

use "debug"


// Implements the LEM 1802 colour monitor's interface, see
// specs/nya_lem1802-1-0.txt.
// TODO: Implement the real thing as an alternative, then change the hardware ID
// for this one.
// TODO: Support colours here; good terminals can handle it.

// NB: Support for custom fonts here is of course not possible naively. We
// could have an alternative to that which uses the 32-bits-per-character of the
// "font" to set the Unicode code point that should be used for displaying that
// character.
// TODO: Maybe implement the above? For now, the default character font is
// sufficient.
actor HWConsole is Device
  let _cpu: CPU tag
  let _env: Env

  let _framerate: U64 = 5

  // These use the defaults when set to 0.
  var _screenMap: U16 = 0
  var _fontMap: U16 = 0
  var _paletteMap: U16 = 0

  var _redrawNeeded: Bool = false

  // This is the Unicode actual font used to write things on the console.
  let _defaultFont: Array[String] val
  // This is the actual default DCPU-16 font in its usual encoding, to dump to
  // the user.
  let _defaultRealFont: Array[U16] val
  let _defaultPalette: Array[U16] val

  let _timers: Timers tag = Timers()
  let _timer: Timer tag


  new create(env: Env, cpu: CPU tag) =>
    // Hide the cursor, clear the screen.
    env.out.write("\x1b[?25l\x1b[2J")
    _env = env
    _cpu = cpu

    _defaultFont = _mkDefaultFont()
    _defaultRealFont = _mkDefaultRealFont()
    _defaultPalette = _mkDefaultPalette()

    let t: Timer iso = Timer(_notify(), 0, 1000000000 / _framerate)
    _timer = t
    _timers(consume t)

    // Signal handlers don't keep the program alive, so I can use this without
    // needing to keep track.
    SignalHandler(object iso is SignalNotify
      let _env: Env = _env
      fun ref apply(count: U32): Bool =>
        _env.out.print("\x1b[?25h") // Make the cursor visible again.
        true
    end, Sig.term())


  fun tag _notify(): TimerNotify iso^ =>
    object iso is TimerNotify
      let parent: HWConsole = this
      fun ref apply(timer: Timer, count: U64): Bool =>
        parent.redraw()
        true // Keep scheduling
    end

  // TODO: I'm lying and claiming to be an LEM1802 even though I don't support
  // all the features.
  fun id(): U32 => 0x7349f615
  fun manufacturer(): U32 => 0x1c6c8b36
  fun version(): U16 => 0x1802

  be hardwareInfo(st: CPUState iso) =>
    _cpu.run(injectHardwareInfo(consume st))

  be redraw() =>
    _redrawNeeded = true

  be interrupt(st: CPUState iso) =>
    try
      let msg = st.regs(0)
      match msg
      | 0 => // Set the screen data memory map location to B. 0 disconnects.
        // TODO: One second is supposed to pass during startup, and show a
        // splash screen, the Nya Eletriska one.
        _screenMap = st.regs(1)
        _redrawNeeded = true
      | 1 => // Set the font memory map location to B. 0 disconnects.
        _fontMap = st.regs(1)
        _redrawNeeded = true
      | 2 => // Set the palette map location to B. 0 disconnects.
        _paletteMap = st.regs(1)
        _redrawNeeded = true
      | 3 => // Set the border color to palette index in B & 0xf.
        None // Do nothing; we don't support the border colour right now.
        // TODO: Supporting that should be possible by drawing a coloured border
        // using wholly-filled blocks around the actual screen area.
        // No point until we have colour support anyway.
        _redrawNeeded = true
      | 4 => // Dump the default font at B.
        // TODO: This takes 256 cycles, which is not modeled.
        var i: U16 = 0
        let b = st.regs(1)
        while i < 256 do
          st.mem((b + i).usize()) = _defaultRealFont(i.usize())
          i = i + 1
        end
      end
    end
    _cpu.run(consume st)


  be tick(index: USize, st: CPUState iso) =>
    // The screen gets invalidated every time something substantial changes, or
    // at 10fps, which is controlled by a timer.
    if _redrawNeeded and (_screenMap != 0) then
      _cpu.hardwareDone(index, _paint(consume st))
    else
      _cpu.hardwareDone(index, consume st)
    end

  fun _paint(st: CPUState iso): CPUState iso^ =>
    // Move the cursor to the top-left.
    // Don't actually clear it - that causes unnecessary flickering.
    _env.out.write("\x1b[H")

    // Read from the mapped area of memory and write each character. Colours are
    // currently ignored.
    try
      var row: USize = 0
      while row < 12 do
        var col: USize = 0
        while col < 32 do
          // Mask off the colours and such.
          let char = 0x7f and st.mem(_screenMap.usize() + (row * 32) + col)
          let str = _defaultFont(char.usize())
          _env.out.write(str)
          col = col + 1
        end
        _env.out.write("\n")
        row = row + 1
      end
    end
    consume st


  be dispose() =>
    _env.out.write("\x1b[?25h") // Show the cursor again.
    _timers.cancel(_timer)


  fun tag _mkDefaultPalette(): Array[U16] val =>
    recover val [
      0x0000, 0x000a, 0x00a0, 0x00aa,
      0x0a00, 0x0a0a, 0x0a50, 0x0aaa,
      0x0555, 0x055f, 0x05f5, 0x05ff,
      0x0f55, 0x0f5f, 0x0ff5, 0x0fff
    ] end

  fun tag _mkDefaultFont(): Array[String] val =>
    recover val
      var font: Array[String val] ref = [
        recover val String.from_utf32(0x2327) end, // For the first four characters, which are
        recover val String.from_utf32(0x2327) end, // four messy blobs, we use U+2327, X IN A
        recover val String.from_utf32(0x2327) end, // RECTANGLE BOX.
        recover val String.from_utf32(0x2327) end,
        recover val String.from_utf32(0x00b1) end, // DCPU 4 - plus/minus - U+b1
        recover val String.from_utf32(0x00f7) end, // DCPU 5 - division sign - U+f7
        recover val String.from_utf32(0x00b7) end, // DCPU 6 - middle dot - U+b7
        recover val String.from_utf32(0x2500) end, // DCPU 7 - center horizontal line - U+2500
        recover val String.from_utf32(0x2502) end, // DCPU 8 - center vertical line - U+2502
        recover val String.from_utf32(0x250c) end, // DCPU 9 - down+right line - U+250c
        recover val String.from_utf32(0x2510) end, // DCPU 10 - down+left line - U+2510
        recover val String.from_utf32(0x2518) end, // DCPU 11 - up+left line - U+2518
        recover val String.from_utf32(0x2514) end, // DCPU 12 - up+right line - U+2514
        recover val String.from_utf32(0x251c) end, // DCPU 13 - vertical+right line - U+251c
        recover val String.from_utf32(0x252c) end, // DCPU 14 - horizontal+down line - U+252c
        recover val String.from_utf32(0x2524) end, // DCPU 15 - vertical+left line - U+2524
        recover val String.from_utf32(0x2534) end, // DCPU 16 - horizontal+up line - U+2534
        recover val String.from_utf32(0x253c) end, // DCPU 17 - cross line - U+253c

        // TODO: These below are approximations to the real DCPU font.
        recover val String.from_utf32(0x2571) end, // DCPU 18 - left diagonal - U+2571
        recover val String.from_utf32(0x2572) end, // DCPU 19 - right diagonal - U+2572
        recover val String.from_utf32(0x25e3) end, // DCPU 20 - southwest half - U+25e3
        recover val String.from_utf32(0x25e4) end, // DCPU 21 - northwest half - U+25e4
        recover val String.from_utf32(0x25e5) end, // DCPU 22 - northeast half - U+25e5
        recover val String.from_utf32(0x25e2) end, // DCPU 23 - southeast half - U+25e2
        recover val String.from_utf32(0x2591) end, // DCPU 24 - light shade - U+2591
        recover val String.from_utf32(0x2592) end, // DCPU 25 - medium shade - U+2592
        recover val String.from_utf32(0x2593) end, // DCPU 26 - dark shade - U+2593
        recover val String.from_utf32(0x2580) end, // DCPU 27 - upper half block - U+2580
        recover val String.from_utf32(0x2584) end, // DCPU 28 - lower half block - U+2584
        recover val String.from_utf32(0x2590) end, // DCPU 29 - right half block - U+2590
        recover val String.from_utf32(0x258c) end, // DCPU 30 - left half block - U+258c
        recover val String.from_utf32(0x258c) end  // DCPU 31 - whole block - U+258c
      ]

      // The next three rows of 32 are ASCII standard, so I just copy them in.
      // Except for the last one, 0x7f. That's DEL in standard and degrees in
      // DCPU.
      var i: U32 = 0x20 // Space
      while i < 0x7f do
        font.push(recover val String.from_utf32(i) end)
        i = i + 1
      end
      // Add the degrees symbol at the end.
      font.push(recover val String.from_utf32(0x00b0) end)

      font
    end


  // Fonts look like this:
  //   word0 = 11111111 /
  //           00001001
  //   word1 = 00001001 /
  //           00000000
  // 128 characters in the character set, two words (four bytes) each, for 256
  // words of font data.

  // The array below encodes the characters in the same fashion.
  fun tag _mkDefaultRealFont(): Array[U16] val =>
    recover val [
      0xb79e, 0x388e, // 0x00 - blob thingy 1
      0x722c, 0x75f4, // 0x01 - blob thingy 2
      0x19bb, 0x7f8f, // 0x02 - blob thingy 3
      0x85f9, 0xb158, // 0x03 - blob thingy 4
      0x242e, 0x2400, // 0x04 - plus/minus
      0x082a, 0x0800, // 0x05 - division
      0x0008, 0x0000, // 0x06 - centered dot
      0x0808, 0x0808, // 0x07 - centered horizontal line
      0x00ff, 0x0000, // 0x08 - centered vertical line
      0x00f8, 0x0808, // 0x09 - outline SE quarter
      0x08f8, 0x0000, // 0x0a - outline SW quarter
      0x080f, 0x0000, // 0x0b - outline NW quarter
      0x000f, 0x0808, // 0x0c - outline NE quarter
      0x00ff, 0x0808, // 0x0d - vertical bar with E leg
      0x08f8, 0x0808, // 0x0e - horizontal bar with S leg
      0x08ff, 0x0000, // 0x0f - vertical bar with W leg

      0x080f, 0x0808, // 0x10 - horizontal bar with N leg
      0x08ff, 0x0808, // 0x11 - cross
      0x6633, 0x99cc, // 0x12 - cross-diagonal lines
      0x9933, 0x66cc, // 0x13 - main-diagonal lines
      0xfef8, 0xe080, // 0x14 - diagonal SW half
      0x7f1f, 0x0301, // 0x15 - diagonal NW half
      0x0107, 0x1f7f, // 0x16 - diagonal NE half
      0x80e0, 0xf8fe, // 0x17 - diagonal SE half
      0x5500, 0xaa00, // 0x18 - dotted lines
      0x55aa, 0x55aa, // 0x19 - checkerboard
      0xffaa, 0xff55, // 0x1a - negative space dotted lines
      0x0f0f, 0x0f0f, // 0x1b - N half
      0xf0f0, 0xf0f0, // 0x1c - S half
      0x0000, 0xffff, // 0x1d - E half
      0xffff, 0x0000, // 0x1e - W half
      0xffff, 0xffff, // 0x1f - wholly filled

      0x0000, 0x0000, // 0x20 - space (wholly empty)
      0x005f, 0x0000, // 0x21 - !
      0x0300, 0x0300, // 0x22 - "
      0x1f05, 0x1f00, // 0x23 - #
      0x266b, 0x3200, // 0x24 - $
      0x611c, 0x4300, // 0x25 - %
      0x3629, 0x7650, // 0x26 - &
      0x0002, 0x0100, // 0x27 - '
      0x1c22, 0x4100, // 0x28 - (
      0x4122, 0x1c00, // 0x29 - )
      0x1408, 0x1400, // 0x2a - *
      0x081c, 0x0800, // 0x2b - +
      0x4020, 0x0000, // 0x2c - ,
      0x8080, 0x8000, // 0x2d - -
      0x0040, 0x0000, // 0x2e - .
      0x601c, 0x0300, // 0x2f - /

      0x3e49, 0x3e00, // 0x30 - 0
      0x427f, 0x4000, // 0x31 - 1
      0x6259, 0x4600, // 0x32 - 2
      0x2249, 0x3600, // 0x33 - 3
      0x0f08, 0x7f00, // 0x34 - 4
      0x2745, 0x3900, // 0x35 - 5
      0x3e49, 0x3200, // 0x36 - 6
      0x6119, 0x0700, // 0x37 - 7
      0x3649, 0x3600, // 0x38 - 8
      0x2649, 0x3e00, // 0x39 - 9
      0x0024, 0x0000, // 0x3a - :
      0x4024, 0x0000, // 0x3b - ;
      0x0814, 0x2200, // 0x3c - <
      0x1414, 0x1400, // 0x3d - =
      0x2214, 0x0800, // 0x3e - >
      0x0259, 0x0600, // 0x3f - ?

      0x3e59, 0x5e00, // 0x40 - @
      0x7e09, 0x7e00, // 0x41 - A
      0x7f49, 0x3600, // 0x42 - B
      0x3e41, 0x2200, // 0x43 - C
      0x7f41, 0x3e00, // 0x44 - D
      0x7f49, 0x4100, // 0x45 - E
      0x7f09, 0x0100, // 0x46 - F
      0x3e41, 0x7a00, // 0x47 - G
      0x7f08, 0x7f00, // 0x48 - H
      0x417f, 0x4100, // 0x49 - I
      0x2040, 0x3f00, // 0x4a - J
      0x7f08, 0x7700, // 0x4b - K
      0x7f40, 0x4000, // 0x4c - L
      0x7f06, 0x7f00, // 0x4d - M
      0x7f01, 0x7e00, // 0x4e - N
      0x3e41, 0x3e00, // 0x4f - O

      0x7f09, 0x0600, // 0x50 - P
      0x3e61, 0x7e00, // 0x51 - Q
      0x7f09, 0x7600, // 0x52 - R
      0x2649, 0x3200, // 0x53 - S
      0x017f, 0x0100, // 0x54 - T
      0x3f40, 0x7f00, // 0x55 - U
      0x1f60, 0x1f00, // 0x56 - V
      0x7f30, 0x7f00, // 0x57 - W
      0x7780, 0x7700, // 0x58 - X
      0x0778, 0x0700, // 0x59 - Y
      0x7149, 0x4700, // 0x5a - Z
      0x007f, 0x4100, // 0x5b - [
      0x031c, 0x6000, // 0x5c - \
      0x417f, 0x0000, // 0x5d - ]
      0x0201, 0x0200, // 0x5e - ^
      0x8080, 0x8000, // 0x5f - _

      0x0001, 0x0200, // 0x60 - `
      0x0204, 0x5400, // 0x61 - a
      0x7f44, 0x3800, // 0x62 - b
      0x3844, 0x2800, // 0x63 - c
      0x3844, 0x7f00, // 0x64 - d
      0x3854, 0x5800, // 0x65 - e
      0x087e, 0x0900, // 0x66 - f
      0x4854, 0x3c00, // 0x67 - g
      0x7f04, 0x7800, // 0x68 - h
      0x047d, 0x0000, // 0x69 - i
      0x2040, 0x3d00, // 0x6a - j
      0x7f10, 0x6c00, // 0x6b - k
      0x017f, 0x0000, // 0x6c - l
      0x7c18, 0x7c00, // 0x6d - m
      0x7c04, 0x7800, // 0x6e - n
      0x3842, 0x3800, // 0x6f - o

      0x7c14, 0x0800, // 0x70 - p
      0x0814, 0x7c00, // 0x71 - q
      0x7c04, 0x0800, // 0x72 - r
      0x4854, 0x2400, // 0x73 - s
      0x043e, 0x4400, // 0x74 - t
      0x3c40, 0x7c00, // 0x75 - u
      0x1c60, 0x1c00, // 0x76 - v
      0x7c30, 0x7c00, // 0x77 - w
      0x6c10, 0x6c00, // 0x78 - x
      0x4c50, 0x3c00, // 0x79 - y
      0x6454, 0x4c00, // 0x7a - z
      0x0836, 0x4100, // 0x7b - {
      0x0077, 0x0000, // 0x7c - |
      0x4136, 0x0800, // 0x7d - }
      0x0201, 0x0201, // 0x7e - ~
      0x0205, 0x0200  // 0x7f - degrees
    ] end

  fun tag sdl_error(): String val =>
    recover val String.copy_cstring(@SDL_GetError[Pointer[U8] box]()) end





