use ".."
use "lib:SDL2"

use "debug"

// SDL calls
use @SDL_Init[I32](flags: U32)
use @SDL_CreateWindow[Pointer[_SDLWindow] tag](title: Pointer[U8] tag,
    x: I32, y: I32, w: I32, h: I32, flags: U32)
use @SDL_CreateRenderer[Pointer[_SDLRenderer] tag](
    window: Pointer[_SDLWindow] tag, index: I32, flags: U32)
use @SDL_CreateTexture[Pointer[_SDLTexture] tag](
    renderer: Pointer[_SDLRenderer] tag, format: U32, access: I32,
    w: I32, h: I32)

use @SDL_UpdateTexture[I32](texture: Pointer[_SDLTexture] tag,
    rect: Pointer[_SDLRect] tag, pixels: Pointer[U8] tag /* void* */,
    pitch: I32)

use @SDL_RenderClear[I32](renderer: Pointer[_SDLRenderer] tag)
use @SDL_RenderCopy[I32](renderer: Pointer[_SDLRenderer] tag,
    texture: Pointer[_SDLTexture] tag,
    srcrect: Pointer[_SDLRect] tag, dstrect: Pointer[_SDLRect] tag)
use @SDL_RenderPresent[None](renderer: Pointer[_SDLRenderer] tag)

use @SDL_DestroyWindow[None](window: Pointer[_SDLWindow] tag)
use @SDL_DestroyRenderer[None](renderer: Pointer[_SDLRenderer] tag)
use @SDL_DestroyTexture[None](texture: Pointer[_SDLTexture] tag)

use @SDL_GetError[Pointer[U8] box]()


primitive _SDLWindow
primitive _SDLRenderer
primitive _SDLTexture
primitive _SDLRect


// Implements the LEM 1802 colour monitor, see specs/nya_lem1802-1-0.txt.
actor HWMonitor is Device
  let _cpu: CPU tag
  let _env: Env

  let width: I32 = 192
  let height: I32 = 96
  let scale: I32 = 1

  // These use the defaults when set to 0.
  var _screenMap: U16 = 0
  var _fontMap: U16 = 0
  var _paletteMap: U16 = 0

  var _borderColor: U16 = 0 // TODO: Double-check the default colour for this.

  var _redrawNeeded: Bool = false

  let _defaultFont: Array[U16] val
  let _defaultPalette: Array[U16] val

  var _pixels: Array[U32] ref = Array[U32].init(0xffffffff, (width * height).usize())

  var _window: Pointer[_SDLWindow] tag
  var _renderer: Pointer[_SDLRenderer] tag
  var _texture: Pointer[_SDLTexture] tag


  new create(env: Env, cpu: CPU tag) =>
    _env = env
    _cpu = cpu

    _defaultFont = _mkDefaultFont()
    _defaultPalette = _mkDefaultPalette()

    let e1 = @SDL_Init[I32](U32(0x0020) /* INIT_VIDEO */)
    if e1 != 0 then
      Debug("SDL_Init failed: " + sdl_error())
    end

    _window = @SDL_CreateWindow[Pointer[_SDLWindow] tag]("Ponyboy".cstring(),
        I32(100), I32(100), (width * scale).i32(),
        (height * scale).i32(), U32(0004))
        // SDL_WINDOW_SHOWN

    _renderer = @SDL_CreateRenderer[Pointer[_SDLRenderer] tag](_window,
        I32(-1), U32(6) /* ACCELERATED | PRESENTVSYNC */)

    _texture = @SDL_CreateTexture[Pointer[_SDLTexture] tag](_renderer,
        U32(0x16362004) /* PIXELFORMAT_ARGB8888 */,
        I32(1), /* TEXTUREACCESS_STREAMING */
        width, height)


  fun id(): U32 => 0x7349f615
  fun manufacturer(): U32 => 0x1c6c8b36
  fun version(): U16 => 0x1802

  be hardwareInfo(st: CPUState iso) =>
    _cpu.run(injectHardwareInfo(consume st))

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
        _borderColor = st.regs(1) and 0xf
        _redrawNeeded = true
      | 4 => // Dump the default font at B.
        // TODO: This takes 256 cycles, which is not modeled.
        var i: U16 = 0
        let b = st.regs(1)
        while i < 256 do
          st.mem((b + i).usize()) = _defaultFont(i.usize())
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
    consume st


  // TODO: Clean up the SDL bits to exit cleanly.
  be dispose() =>
    @SDL_DestroyTexture[None](_texture)
    @SDL_DestroyRenderer[None](_renderer)
    @SDL_DestroyWindow[None](_window)
    @SDL_Quit[None]()


  fun tag _mkDefaultPalette(): Array[U16] val =>
    recover val [
      0x0000, 0x000a, 0x00a0, 0x00aa,
      0x0a00, 0x0a0a, 0x0a50, 0x0aaa,
      0x0555, 0x055f, 0x05f5, 0x05ff,
      0x0f55, 0x0f5f, 0x0ff5, 0x0fff
    ] end

  // Fonts look like this:
  //   word0 = 11111111 /
  //           00001001
  //   word1 = 00001001 /
  //           00000000
  // 128 characters in the character set, two words (four bytes) each, for 256
  // words of font data.

  // The array below encodes the characters in the same fashion.
  fun tag _mkDefaultFont(): Array[U16] val =>
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





