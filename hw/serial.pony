use ".."
use "collections"

trait Device
  fun id(): U32
  fun manufacturer(): U32
  fun version(): U16

  fun injectHardwareInfo(st: CPUState iso): CPUState iso^ =>
    try
      var x = id()
      st.regs(0) = x.u16()
      st.regs(1) = (x >> 16).u16()
      var y = manufacturer()
      st.regs(3) = y.u16()
      st.regs(4) = (y >> 16).u16()
      st.regs(2) = version()
    end
    consume st

  be tick(index: USize, st: CPUState iso)
  be hardwareInfo(st: CPUState iso)
  be interrupt(st: CPUState iso)


// This is an invented serial I/O device I made up for easy console debugging.
// It's essentially a serial console.
// Triggers an interrupt for each incoming character when the message is
// nonzero.
// On a hardware interrupt, does the following:
// A = 0: Sets the interrupt message to B. 0 disables interrupts (default).
// A = 1: Sets B to the last input character.
// A = 2: Emits B as an ASCII character.
actor HWSerial is Device
  let _cpu: CPU tag
  let _env: Env

  var _message: U16 = 0
  var _interruptsRemaining: USize = 0

  var _queue: List[U8 val] ref = List[U8]()

  new create(env: Env, cpu: CPU tag) =>
    _env = env
    _cpu = cpu
    env.input(_notify())

  fun tag _notify(): StdinNotify iso^ =>
    object iso is StdinNotify
      let parent: HWSerial = this
      fun ref apply(data: Array[U8] iso) => parent._newData(consume data)
    end

  be _newData(data: Array[U8] val) =>
    for c in data.values() do
      _queue.push(c)
      _interruptsRemaining = _interruptsRemaining + 1
    end

  fun id(): U32 => 0x12345678
  fun manufacturer(): U32 => 0x9abcdef0
  fun version(): U16 => 1

  be hardwareInfo(st: CPUState iso) =>
    _cpu.run(injectHardwareInfo(consume st))

  be interrupt(st: CPUState iso) =>
    try
      let msg = st.regs(0)
      match msg
      | 0 =>
        _message = st.regs(1)
      | 1 =>
        st.regs(1) = try _queue.shift().u16() else 0xff end
      | 2 =>
        _env.out.write(recover val [try st.regs(1).u8() else ' ' end] end)
      end
    end
    _cpu.run(consume st)

  be tick(index: USize, st: CPUState iso) =>
    // If _message is nonzero and the queue isn't empty, trigger an interrupt.
    if (_message != 0) and (_interruptsRemaining > 0) then
      _cpu.triggerInterrupt(_message)
      _interruptsRemaining = _interruptsRemaining - 1
    end

    _cpu.hardwareDone(index, consume st)

