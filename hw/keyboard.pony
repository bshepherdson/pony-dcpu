use ".."
use "collections"

use "debug"

// Implements the standard Generic Keyboard DCPU-16 device, reading from the
// user's terminal.
actor HWKeyboard is Device
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
      let parent: HWKeyboard = this
      fun ref apply(data: Array[U8] iso) => parent._newData(consume data)
    end

  be _newData(data: Array[U8] val) =>
    for c in data.values() do
      _queue.push(c)
      _interruptsRemaining = _interruptsRemaining + 1
    end

  fun id(): U32 => 0x30cf7406
  fun manufacturer(): U32 => 0x0 // Generic has no manufacturer.
  fun version(): U16 => 1

  be hardwareInfo(st: CPUState iso) =>
    _cpu.run(injectHardwareInfo(consume st))

  be interrupt(st: CPUState iso) =>
    try
      let msg = st.regs(0)
      match msg
      | 0 => // Clear the buffer.
        _queue.clear()
      | 1 => // Store the next key from the queue into C, 0 if buffer empty.
        st.regs(2) = try _queue.shift().u16() else 0 end
      | 2 => // Set C to 1 if the specified key is pressed now.
        // TODO: Implement this properly once I'm using SDL input, for now it
        // just always returns false.
        st.regs(2) = 0
      | 3 => // Set the interrupt message to B. Disabled if B = 0.
        _message = st.regs(1)
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

  be dispose() =>
    _env.input.dispose()

