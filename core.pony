use "hw"
use "files"
use "collections"

use "debug"

class CPUState
  var mem: Array[U16] iso
  var regs: Array[U16] iso = recover iso Array[U16].init(where from = 0, len = 8) end
  var pc: U16 = 0
  var ex: U16 = 0
  var sp: U16 = 0
  var ia: U16 = 0

  new create(m: Array[U16] iso) =>
    mem = consume m

  fun ref push(x: U16) =>
    sp = sp - 1
    try mem(sp.usize()) = x end

  fun ref pop(): U16 =>
    let r = try mem(sp.usize()) else 0 end
    sp = sp + 1
    r

actor CPU
  var _state: (CPUState iso | None) = None
  var _intQueueing: Bool = false
  var _intQueue: List[U16] = List[U16]()

  var _skipping: Bool = false

  let _env: Env

  var _hardware: Array[Device tag]

  let fmtWord: FormatSettingsInt = FormatSettingsInt.set_format(FormatHexBare)
      .set_width(4)
      .set_fill('0')

  new fromFile(env: Env, file: FilePath) =>
    _env = env
    //let serial: Device tag = HWSerial(env, this)
    let console: Device tag = HWConsole(env, this)
    _hardware = [console]
    var m = recover Array[U16].init(where from = 0, len = 0x10000) end
    try
      with f = OpenFile(file) as File do
        var contents: Array[U8] iso = f.read(f.size())
        var i: USize = 0
        try
          while i < contents.size() do
            let c = (contents(i).u16() << 8) or contents(i + 1).u16()
            m(i / 2) = c
            i = i + 2
          end
        else
          _env.out.print("Failed to load the binary file")
          @exit[None](U32(1))
        end
      end
    else
      _env.out.print("Failed to open target file")
    end

    let s = recover CPUState(consume m) end

    // Starts the CPU running with the first behavior call.
    run(consume s)

  // Here's the flow of behaviors in the system:
  // run(CPUState iso): Entry point that begins the next instruction cycle.
  //   Called at the end of create() and by async opcodes like HWI.
  // tickHardware(USize, CPUState iso): Called repeatedly with successively
  //   higher indexes. This calls tick(USize, CPUState iso) on the hardware at
  //   index, which should call back tickHardware(index + 1, state).
  //   When there's no hardware at that index, calls through to _exec()
  // _exec(): Internal, synchronous opcode runner. Decodes the next op, and
  //   calls it. Most ops are synchronous, so they just end by calling _continue
  //   Any async ops like HWI will eventually call run().
  be run(st: CPUState iso) =>
    _tickHardware(0, consume st)

  fun ref _tickHardware(index: USize, st: CPUState iso) =>
    if index < _hardware.size() then
      try
        let hw = _hardware(index)
        hw.tick(index, consume st)
      end
    else
      // Couldn't look up the _hardware at index, so we've run out of hardware.
      // Call through to the next round of the behavior: checking for
      // interrupts.
      _state = consume st
      _exec()
    end

  be triggerInterrupt(msg: U16) =>
    _intQueue.push(msg)

  be hardwareDone(index: USize, st: CPUState iso) =>
    _tickHardware(index + 1, consume st)

  be dispose() =>
    """Tears down all hardware and kills the process."""
    // Just wipe out the pointers to the hardware devices.
    for h in _hardware.values() do
      h.dispose()
    end

  fun ref _exec() =>
    _checkInterrupts()
    _execOp()

  // Shim for the synchronous ops, which is most of them.
  // Just calls the async _run with the state.
  fun ref _continue() =>
    match _state = None
    | None => _env.out.print("Impossible: _continue called with no state")
    | let st: CPUState iso => run(consume st)
    end


  fun read(addr: U16): U16 => try (_state as CPUState iso).mem(addr.usize()) else 0 end

  fun pcPeek(): U16 => try read((_state as CPUState iso).pc) else 0 end
  fun ref pcGet(): U16 =>
    try
      let pc = (_state as CPUState iso).pc
      let ret = read(pc)
      (_state as CPUState iso).pc = pc + 1
      ret
    else
      0
    end

  fun ref write(addr: U16, value: U16) =>
    try (_state as CPUState iso).mem(addr.usize()) = value end

  fun ref push(x: U16) => try (_state as CPUState iso).push(x) end
  fun ref pop(): U16 => try (_state as CPUState iso).pop() else 0 end

  fun ref _checkInterrupts() =>
    // At most one interrupt is handled between real instructions.
    // If queueing is enabled, just return.
    if _intQueueing or (_intQueue.size() == 0) then
      return
    end

    // Otherwise, we pop the first one.
    try
      let int = _intQueue.shift()
      let st = (_state = None) as CPUState iso^
      //let st = match _state = None | let s: CPUState iso => consume s else error end
      if st.ia != 0 then
        _intQueueing = true
        st.push(st.pc)
        st.push(st.regs(0))
        st.regs(0) = int
        st.pc = st.ia
      end
      _state = consume st
    end

  fun ref _execOp() =>
    // Read the word at PC, decode it, and call the right function.
    let pc = try (_state as CPUState iso).pc else 0 end
    let op = pcGet()
    Debug.err("Executing at " + pc.string(fmtWord) + ": " + op.string(fmtWord))
    try
      match _state = None
      | None => error
      | let st: CPUState iso =>
        Debug.err("PC = " + st.pc.string(fmtWord) + " " +
          "A = " + st.regs(0).string(fmtWord) + " " +
          "B = " + st.regs(1).string(fmtWord) + " " +
          "C = " + st.regs(2).string(fmtWord) + " " +
          "X = " + st.regs(3).string(fmtWord) + " " +
          "Y = " + st.regs(4).string(fmtWord) + " " +
          "Z = " + st.regs(5).string(fmtWord) + " " +
          "I = " + st.regs(6).string(fmtWord) + " " +
          "J = " + st.regs(7).string(fmtWord) + " " +
          "SP = " + st.sp.string(fmtWord))
        _state = consume st
      end
    end
    let opcode = op and 31
    let a = (op >> 10) and 63
    let b = (op >> 5) and 31

    // Special case for skipping.
    if _skipping then
      // We won't really perform this instruction. Instead, we consume its
      // arguments without evaluating them (PUSH, POP are destructive).
      consumeArg(a)
      if opcode != 0 then
        consumeArg(b)
      end

      // If the operation skipping was a branch (0x10 <= opcode < 0x18) then we
      // continue skipping.
      _skipping = (0x10 <= opcode) and (opcode < 0x18)
      _continue()
      return
    end

    if opcode == 0 then
      // Special opcodes. a is the argument, b is the actual opcode.
      match b
      | 0x01 => op_jsr(a); _continue()
      | 0x08 => op_int(a); _continue()
      | 0x09 => op_iag(a); _continue()
      | 0x0a => op_ias(a); _continue()
      | 0x0b => op_rfi(a); _continue()
      | 0x0c => op_iaq(a); _continue()
      | 0x10 => op_hwn(a); _continue()
      | 0x11 => op_hwq(a) // Async, no continue
      | 0x12 => op_hwi(a) // Async, no continue
      // Nonstandard, but useful
      | 0x07 => op_hcf(a) // Deliberately no continue here.
      else
        _env.out.print("ERROR: Illegal special opcode " + b.string())
      end
    else
      match opcode
      | 0x01 => op_set(a, b)
      | 0x02 => op_add(a, b)
      | 0x03 => op_sub(a, b)
      | 0x04 => op_mul(a, b)
      | 0x05 => op_mli(a, b)
      | 0x06 => op_div(a, b)
      | 0x07 => op_dvi(a, b)
      | 0x08 => op_mod(a, b)
      | 0x09 => op_mdi(a, b)
      | 0x0a => op_and(a, b)
      | 0x0b => op_bor(a, b)
      | 0x0c => op_xor(a, b)
      | 0x0d => op_shr(a, b)
      | 0x0e => op_asr(a, b)
      | 0x0f => op_shl(a, b)
      | 0x10 => op_ifb(a, b)
      | 0x11 => op_ifc(a, b)
      | 0x12 => op_ife(a, b)
      | 0x13 => op_ifn(a, b)
      | 0x14 => op_ifg(a, b)
      | 0x15 => op_ifa(a, b)
      | 0x16 => op_ifl(a, b)
      | 0x17 => op_ifu(a, b)
      | 0x1a => op_adx(a, b)
      | 0x1b => op_sbx(a, b)
      | 0x1e => op_sti(a, b)
      | 0x1f => op_std(a, b)
      else
        _env.out.print("ERROR: Illegal normal opcode " + opcode.string())
      end

      // All of the normal ops are synchronous, so always _continue.
      _continue()
    end

  fun ref readArg(arg: U16, movePC: Bool = true): U16 =>
    try
      if arg < 8 then
        (_state as CPUState iso).regs(arg.usize())
      elseif arg < 16 then
        read((_state as CPUState iso).regs((arg - 8).usize()))
      elseif arg < 24 then
        let next = if movePC then pcGet() else pcPeek() end
        read((_state as CPUState iso).regs((arg - 16).usize()) + next)
      elseif arg == 0x18 then // POP/PEEK
        if movePC then // POP
          pop()
        else // PEEK
          read((_state as CPUState iso).sp)
        end
      elseif arg == 0x19 then // [SP]/PEEK
        read((_state as CPUState iso).sp)
      elseif arg == 0x1a then // PICK n
        read((_state as CPUState iso).sp + (if movePC then pcGet() else pcPeek() end))
      elseif arg == 0x1b then // SP
        (_state as CPUState iso).sp
      elseif arg == 0x1c then // PC
        (_state as CPUState iso).pc
      elseif arg == 0x1d then // EX
        (_state as CPUState iso).ex
      elseif arg == 0x1e then // [next word]
        read(if movePC then pcGet() else pcPeek() end)
      elseif arg == 0x1f then // next word (literal)
        if movePC then pcGet() else pcPeek() end
      else // inline literal
        arg - 0x21
      end
    else
      0
    end

  fun ref writeArg(arg: U16, value: U16) =>
    try
      if arg < 8 then
        (_state as CPUState iso).regs(arg.usize()) = value
      elseif arg < 16 then
        write((_state as CPUState iso).regs((arg - 8).usize()), value)
      elseif arg < 24 then
        write((_state as CPUState iso).regs((arg - 16).usize()) + pcGet(), value)
      elseif arg == 0x18 then // PUSH
        push(value)
      elseif arg == 0x19 then // PEEK
        write((_state as CPUState iso).sp, value)
      elseif arg == 0x1a then // PICK n
        write((_state as CPUState iso).sp + pcGet(), value)
      elseif arg == 0x1b then // SP
        (_state as CPUState iso).sp = value
      elseif arg == 0x1c then // PC
        (_state as CPUState iso).pc = value
      elseif arg == 0x1d then // EX
        (_state as CPUState iso).ex = value
      elseif arg == 0x1e then // [next word]
        write(pcGet(), value)
      end
      // Other cases are literals, which silently fail.
    end

  fun ref consumeArg(arg: U16) =>
    // [reg + next word]                   PICK n           [next word]
    if ((0x10 <= arg) and (arg < 0x18)) or (arg == 0x1a) or (arg == 0x1e) or
        // next word (literal)
        (arg == 0x1f) then
      try
        let st = (_state = None) as CPUState iso^
        st.pc = st.pc + 1
        _state = consume st
      end
    end


  fun ref _mathEx(a: U16, b: U16, op: {(U16, U16): (U16, U16)} val) =>
    let av = readArg(a)
    let bv = readArg(b, false)
    (let res, let carry) = op(av, bv)
    writeArg(b, res)
    try (_state as CPUState iso).ex = carry end

  fun ref _math(a: U16, b: U16, op: {(U16, U16): U16} val) =>
    let av = readArg(a)
    let bv = readArg(b, false)
    writeArg(b, op(av, bv))

  fun ref op_set(a: U16, b: U16) =>Debug.err("op_set: " + b.string(fmtWord) + ", " +
  a.string(fmtWord)); writeArg(b, readArg(a))

  fun ref op_add(a: U16, b: U16) =>Debug.err("op_add: " + b.string(fmtWord) + ", " +
  a.string(fmtWord)); _mathEx(a, b, lambda(av: U16, bv: U16): (U16, U16) =>
    let res = av.u32() + bv.u32()
    ((res and 0xffff).u16(), if res >= 0x10000 then 1 else 0 end)
  end)

  fun ref op_sub(a: U16, b: U16) =>Debug.err("op_sub: " + b.string(fmtWord) + ", " +
  a.string(fmtWord)); _mathEx(a, b, lambda(av: U16, bv: U16): (U16, U16) =>
    let res = bv.u32() - av.u32()
    ((res and 0xffff).u16(), if (res and 0x80000000) == 0 then 0 else 0xffff end)
  end)

  fun ref op_mul(a: U16, b: U16) =>Debug.err("op_mul: " + b.string(fmtWord) + ", " +
  a.string(fmtWord)); _mathEx(a, b, lambda(av: U16, bv: U16): (U16, U16) =>
    let res = av.u32() * bv.u32()
    ((res and 0xffff).u16(), (res >> 16).u16())
  end)

  fun ref op_mli(a: U16, b: U16) =>Debug.err("op_mli: " + b.string(fmtWord) + ", " +
  a.string(fmtWord)); _mathEx(a, b, lambda(av: U16, bv: U16): (U16, U16) =>
    let res = av.i16().i32() * bv.i16().i32()
    ((res and 0xffff).u16(), (res >> 16).u16())
  end)

  fun ref op_div(a: U16, b: U16) =>Debug.err("op_div: " + b.string(fmtWord) + ", " +
  a.string(fmtWord)); _mathEx(a, b, lambda(av: U16, bv: U16): (U16, U16) =>
    if av == 0 then (0, 0) else
      (bv / av, ((bv.u32() << 16) / av.u32()).u16())
    end
  end)

  fun ref op_dvi(a: U16, b: U16) =>Debug.err("op_dvi: " + b.string(fmtWord) + ", " +
  a.string(fmtWord)); _mathEx(a, b, lambda(av: U16, bv: U16): (U16, U16) =>
    if av == 0 then (0, 0) else
      ((bv.i16() / av.i16()).u16(), ((bv.i16().i32() << 16) / av.i16().i32()).u16())
    end
  end)

  fun ref op_mod(a: U16, b: U16) =>Debug.err("op_mod: " + b.string(fmtWord) + ", " +
  a.string(fmtWord)); _math(a, b, lambda(av: U16, bv: U16): U16 =>
    if av == 0 then 0 else bv % av end
  end)

  fun ref op_mdi(a: U16, b: U16) =>Debug.err("op_mdi: " + b.string(fmtWord) + ", " +
  a.string(fmtWord)); _math(a, b, lambda(av: U16, bv: U16): U16 =>
    if av == 0 then 0 else (bv.i16() % av.i16()).u16() end
  end)

  fun ref op_and(a: U16, b: U16) =>Debug.err("op_and: " + b.string(fmtWord) + ", " +
  a.string(fmtWord)); _math(a, b, lambda(av: U16, bv: U16): U16 =>
    av and bv
  end)
  fun ref op_bor(a: U16, b: U16) =>Debug.err("op_bor: " + b.string(fmtWord) + ", " +
  a.string(fmtWord)); _math(a, b, lambda(av: U16, bv: U16): U16 =>
    av or bv
  end)
  fun ref op_xor(a: U16, b: U16) =>Debug.err("op_xor: " + b.string(fmtWord) + ", " +
  a.string(fmtWord)); _math(a, b, lambda(av: U16, bv: U16): U16 =>
    av xor bv
  end)

  fun ref op_shr(a: U16, b: U16) =>Debug.err("op_shr: " + b.string(fmtWord) + ", " +
  a.string(fmtWord)); _mathEx(a, b, lambda(av: U16, bv: U16): (U16, U16) =>
    (bv >> av, ((bv.u32() << 16) >> av.u32()).u16())
  end)
  fun ref op_asr(a: U16, b: U16) =>Debug.err("op_asr: " + b.string(fmtWord) + ", " +
  a.string(fmtWord)); _mathEx(a, b, lambda(av: U16, bv: U16): (U16, U16) =>
    ((bv.i16() >> av.i16()).u16(), ((bv.i16().i32() << 16) >> av.u32().i32()).u16())
  end)
  fun ref op_shl(a: U16, b: U16) =>Debug.err("op_shl: " + b.string(fmtWord) + ", " +
  a.string(fmtWord)); _mathEx(a, b, lambda(av: U16, bv: U16): (U16, U16) =>
    (bv << av, ((bv.u32() << av.u32()) >> 16).u16())
  end)

  fun ref _branch(a: U16, b: U16, op: {(U16, U16): Bool} val) =>
    let av = readArg(a)
    let bv = readArg(b)
    _skipping = not op(av, bv)

  fun ref op_ifb(a: U16, b: U16) =>Debug.err("op_ifb: " + b.string(fmtWord) + ", " +
  a.string(fmtWord)); _branch(a, b, lambda(av: U16, bv: U16): Bool =>
    (av and bv) != 0
  end)
  fun ref op_ifc(a: U16, b: U16) =>Debug.err("op_ifc: " + b.string(fmtWord) + ", " +
  a.string(fmtWord)); _branch(a, b, lambda(av: U16, bv: U16): Bool =>
    (av and bv) == 0
  end)
  fun ref op_ife(a: U16, b: U16) =>Debug.err("op_ife: " + b.string(fmtWord) + ", " +
  a.string(fmtWord)); _branch(a, b, lambda(av: U16, bv: U16): Bool =>
    Debug.err("op_ife innards: " + av.string() + " == " + bv.string() +
    " is " + (av == bv).string())
    av == bv
  end)
  fun ref op_ifn(a: U16, b: U16) =>Debug.err("op_ifn: " + b.string(fmtWord) + ", " +
  a.string(fmtWord)); _branch(a, b, lambda(av: U16, bv: U16): Bool =>
    av != bv
  end)
  fun ref op_ifg(a: U16, b: U16) =>Debug.err("op_ifg: " + b.string(fmtWord) + ", " +
  a.string(fmtWord)); _branch(a, b, lambda(av: U16, bv: U16): Bool =>
    bv > av
  end)
  fun ref op_ifa(a: U16, b: U16) =>Debug.err("op_ifa: " + b.string(fmtWord) + ", " +
  a.string(fmtWord)); _branch(a, b, lambda(av: U16, bv: U16): Bool =>
    bv.i16() > av.i16()
  end)
  fun ref op_ifl(a: U16, b: U16) =>Debug.err("op_ifl: " + b.string(fmtWord) + ", " +
  a.string(fmtWord)); _branch(a, b, lambda(av: U16, bv: U16): Bool =>
    bv < av
  end)
  fun ref op_ifu(a: U16, b: U16) =>Debug.err("op_ifu: " + b.string(fmtWord) + ", " +
  a.string(fmtWord)); _branch(a, b, lambda(av: U16, bv: U16): Bool =>
    bv.i16() < av.i16()
  end)


  fun ref op_adx(a: U16, b: U16) =>Debug.err("op_adx: " + b.string(fmtWord) + ", " +
  a.string(fmtWord))
    try
      let av = readArg(a)
      let bv = readArg(b, false)
      let res = bv.u32() + av.u32() + (_state as CPUState iso).ex.u32()
      writeArg(b, res.u16())
      (_state as CPUState iso).ex = if res > 0xffff then 1 else 0 end
    end

  // TODO: Double-check these two are correct, especially SBX.
  fun ref op_sbx(a: U16, b: U16) =>Debug.err("op_sbx: " + b.string(fmtWord) + ", " +
  a.string(fmtWord))
    try
      let av = readArg(a)
      let bv = readArg(b, false)
      let res = ((0x10000 or bv.u32()) - av.u32()) + (_state as CPUState iso).ex.u32()
      writeArg(b, res.u16())
      (_state as CPUState iso).ex = if (res and 0xffff0000) == 0 then 0 else 0xffff end
    end

  fun ref op_sti(a: U16, b: U16) =>Debug.err("op_sti: " + b.string(fmtWord) + ", " +
  a.string(fmtWord))
    writeArg(b, readArg(a))
    try
      let st = (_state = None) as CPUState iso^
      st.regs(6) = st.regs(6) + 1
      st.regs(7) = st.regs(7) + 1
      _state = consume st
    end

  fun ref op_std(a: U16, b: U16) =>Debug.err("op_std: " + b.string(fmtWord) + ", " +
  a.string(fmtWord))
    writeArg(b, readArg(a))
    try
      let st = (_state = None) as CPUState iso^
      st.regs(6) = st.regs(6) - 1
      st.regs(7) = st.regs(7) - 1
      _state = consume st
    end


  // Special opcodes
  fun ref op_jsr(a: U16) =>Debug.err("op_jsr: " + a.string(fmtWord))
    try
      let newPC = readArg(a)
      push((_state as CPUState iso).pc)
      (_state as CPUState iso).pc = newPC
    end

  fun ref op_int(a: U16) =>Debug.err("op_int: " + a.string(fmtWord))
    // Queue up the given interrupt.
    _intQueue.push(readArg(a))

  fun ref op_iag(a: U16) =>Debug.err("op_iag: " + a.string(fmtWord)); try writeArg(a, (_state as CPUState iso).ia) end
  fun ref op_ias(a: U16) =>Debug.err("op_ias: " + a.string(fmtWord)); try (_state as CPUState iso).ia = readArg(a) end

  fun ref op_rfi(a: U16) =>Debug.err("op_rfi: " + a.string(fmtWord))
    readArg(a) // Throw away the value.
    _intQueueing = false
    try
      (_state as CPUState iso).regs(0) = pop()
      (_state as CPUState iso).pc = pop()
    end

  fun ref op_iaq(a: U16) =>Debug.err("op_iaq: " + a.string(fmtWord))
    _intQueueing = readArg(a) != 0

  fun ref op_hwn(a: U16) =>Debug.err("op_hwn: " + a.string(fmtWord))
    writeArg(a, _hardware.size().u16())

  fun ref op_hwq(a: U16) =>Debug.err("op_hwq: " + a.string(fmtWord))
    let index = readArg(a)
    let hw = try _hardware(index.usize()) end

    try
      let st = (_state = None) as CPUState iso^
      match hw
      | None =>
        st.regs(0) = 0
        st.regs(1) = 0
        st.regs(2) = 0
        st.regs(3) = 0
        st.regs(4) = 0
        _state = consume st
        _continue() // Need to call this, since this op is sometimes async.
      | let d: Device tag =>
        d.hardwareInfo(consume st) // Will eventually call run()
      end
    end


  fun ref op_hwi(a: U16) =>Debug.err("op_hwi: " + a.string(fmtWord))
    let index = readArg(a)
    let hw = try _hardware(index.usize()) end

    try
      let st = (_state = None) as CPUState iso^
      match hw
      | None => // No such hardware, do nothing.
        _state = consume st
        _continue() // Need to call this, since this op is sometimes async.
      | let d: Device tag =>
        d.interrupt(consume st) // Will eventually call run()
      end
    end

  fun ref op_hcf(a: U16) =>Debug.err("op_hcf: " + a.string(fmtWord))
    let code = readArg(a)
    _env.out.print("[Halt and catch fire: " + code.string(fmtWord) + "]")
    dispose()

