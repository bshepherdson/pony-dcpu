use ".."
use "time"


actor HWClock is Device
  let _cpu: CPU tag
  let _env: Env

  var _tickRate: U16 = 0 // Start disabled
  var _msg: U16 = 0
  var _counter: U16 = 0
  var _innerCounter: U16 = 0

  let _timers: Timers tag = Timers()
  let _timer: Timer tag


  new create(env: Env, cpu: CPU tag) =>
    _env = env
    _cpu = cpu

    let t: Timer iso = Timer(_notify(), 0, 1000000000 / 60)
    _timer = t
    _timers(consume t)


  fun tag _notify(): TimerNotify iso^ =>
    object iso is TimerNotify
      let parent: HWClock = this
      fun ref apply(timer: Timer, count: U64): Bool =>
        parent.clock()
        true // Keep scheduling
    end

  fun id(): U32 => 0x12d0b402
  fun manufacturer(): U32 => 0x00000000 // Generic
  fun version(): U16 => 1

  be hardwareInfo(st: CPUState iso) =>
    _cpu.run(injectHardwareInfo(consume st))

  be interrupt(st: CPUState iso) =>
    try
      let msg = st.regs(0)
      match msg
      | 0 => // Sets the clock speed to 60/B. 0 disables.
        _counter = 0
        _innerCounter = 0
        _tickRate = st.regs(1)
      | 1 => // Store the number of ticks in C.
        st.regs(2) = _counter
      | 2 => // Set interrupt message to B.
        _msg = st.regs(1)
      end
    end
    _cpu.run(consume st)


  // NB: This is the system tick. See clock() for the timer itself.
  be tick(index: USize, st: CPUState iso) =>
    _cpu.hardwareDone(index, consume st)

  be dispose() =>
    _timers.cancel(_timer)

  be clock() =>
    if _tickRate == 0 then return end

    _innerCounter = _innerCounter + 1
    if _innerCounter >= _tickRate then
      _innerCounter = 0
      _counter = _counter + 1
      if _msg != 0 then
        _cpu.triggerInterrupt(_msg)
      end
    end


