use ".."

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
  be dispose()

