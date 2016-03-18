use "files"
use "collections"

class CPU
  var mem: Array[U16] = Array[U16].init(where from = 0, len = 0x10000)
  var regs: Array[U16] = Array[U16].init(where from = 0, len = 8)
  var pc: U16 = 0
  var ex: U16 = 0
  var sp: U16 = 0
  var ia: U16 = 0

  var skipping: Bool = false

  var _intQueueing: Bool = false
  var _intQueue: List[U16] = List[U16]()

  let _env: Env

  new fromFile(env: Env, file: FilePath) =>
    _env = env
    try
      with f = OpenFile(file) as File do
        var contents: Array[U8] iso = f.read(f.size())
        var i: USize = 0
        try
          while i < contents.size() do
            let c = (contents(i).u16() << 8) or contents(i + 1).u16()
            mem(i / 2) = c
            i = i + 2
          end
        else
          _env.out.print("Failed to load the binary file")
          return
        end
      end
    else
      _env.out.print("Failed to open target file")
    end

  fun ref run() =>
    while true do
      _exec()
    end


  fun ref _exec() =>
    """
    Runs a single cycle of the CPU.

    Basic steps:
    - Tick the hardware.
    - Check for interrupts.
    - Read and execute an instruction.
    """

    _tickHardware()
    _checkInterrupts()
    _execOp()


  fun read(addr: U16): U16 => try mem(addr.usize()) else 0 end

  fun pcPeek(): U16 => read(pc)
  fun ref pcGet(): U16 => read(pc = pc + 1)

  fun ref write(addr: U16, value: U16) =>
    try mem(addr.usize()) = value end

  fun ref push(x: U16) =>
    sp = sp - 1
    write(sp, x)
  fun ref pop(): U16 =>
    let r = read(sp)
    sp = sp + 1


  fun ref _tickHardware() => None

  fun ref _checkInterrupts() =>
    // At most one interrupt is handled between real instructions.
    // If queueing is enabled, just return.
    if _intQueueing or (_intQueue.size() == 0) then
      return
    end

    // Otherwise, we pop the first one.
    try
      let int = _intQueue.shift()
      if ia != 0 then
        _intQueueing = true
        push(pc)
        push(regs(0))
        regs(0) = int
        pc = ia
      end
    end

  fun ref _execOp() =>
    // Read the word at PC, decode it, and call the right function.
    let op = read(pc)
    let opcode = op and 31
    let a = (op >> 10) and 63
    let b = (op >> 5) and 31

    // Special case for skipping.
    if skipping then
      // We won't really perform this instruction. Instead, we consume its
      // arguments without evaluating them (PUSH, POP are destructive).
      consumeArg(a)
      if opcode != 0 then
        consumeArg(b)
      end

      // If the operation skipping was a branch (0x10 <= opcode < 0x18) then we
      // continue skipping.
      skipping = (0x10 <= opcode) and (opcode < 0x18)
      return
    end

    if opcode == 0 then
      // Special opcodes. a is the argument, b is the actual opcode.
      match b
      | 0x01 => op_jsr(a)
      | 0x08 => op_int(a)
      | 0x09 => op_iag(a)
      | 0x0a => op_ias(a)
      | 0x0b => op_rfi(a)
      | 0x0c => op_iaq(a)
      | 0x10 => op_hwn(a)
      | 0x11 => op_hwq(a)
      | 0x12 => op_hwi(a)
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
    end

  fun ref readArg(arg: U16, movePC: Bool = true): U16 =>
    try
      if arg < 8 then
        regs(arg.usize())
      elseif arg < 16 then
        read(regs((arg - 8).usize()))
      elseif arg < 24 then
        let next = if movePC then pcGet() else pcPeek() end
        read(regs((arg - 16).usize()) + next)
      elseif arg == 0x18 then // POP/PEEK
        if movePC then // POP
          read(sp = sp + 1)
        else // PEEK
          read(sp)
        end
      elseif arg == 0x19 then // [SP]/PEEK
        read(sp)
      elseif arg == 0x1a then // PICK n
        read(sp + (if movePC then pcGet() else pcPeek() end))
      elseif arg == 0x1b then // SP
        sp
      elseif arg == 0x1c then // PC
        pc
      elseif arg == 0x1d then // EX
        ex
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
        regs(arg.usize()) = value
      elseif arg < 16 then
        write(regs((arg - 8).usize()), value)
      elseif arg < 24 then
        write(regs((arg - 16).usize()) + pcGet(), value)
      elseif arg == 0x18 then // PUSH
        sp = sp - 1
        write(sp, value)
      elseif arg == 0x19 then // PEEK
        write(sp, value)
      elseif arg == 0x1a then // PICK n
        write(sp + pcGet(), value)
      elseif arg == 0x1b then // SP
        sp = value
      elseif arg == 0x1c then // PC
        pc = value
      elseif arg == 0x1d then // EX
        ex = value
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
      pc = pc + 1
    end


  fun ref _mathEx(a: U16, b: U16, op: {(U16, U16): (U16, U16)} val) =>
    let av = readArg(a)
    let bv = readArg(b, false)
    (let res, let carry) = op(av, bv)
    writeArg(b, res)
    ex = carry

  fun ref _math(a: U16, b: U16, op: {(U16, U16): U16} val) =>
    let av = readArg(a)
    let bv = readArg(b, false)
    writeArg(b, op(av, bv))

  fun ref op_set(a: U16, b: U16) => writeArg(b, readArg(a))

  fun ref op_add(a: U16, b: U16) => _mathEx(a, b, lambda(av: U16, bv: U16): (U16, U16) =>
    let res = av.u32() + bv.u32()
    ((res and 0xffff).u16(), if res >= 0x10000 then 1 else 0 end)
  end)

  fun ref op_sub(a: U16, b: U16) => _mathEx(a, b, lambda(av: U16, bv: U16): (U16, U16) =>
    let res = bv.u32() - av.u32()
    ((res and 0xffff).u16(), if (res and 0x80000000) == 0 then 0 else 0xffff end)
  end)

  fun ref op_mul(a: U16, b: U16) => _mathEx(a, b, lambda(av: U16, bv: U16): (U16, U16) =>
    let res = av.u32() * bv.u32()
    ((res and 0xffff).u16(), (res >> 16).u16())
  end)

  fun ref op_mli(a: U16, b: U16) => _mathEx(a, b, lambda(av: U16, bv: U16): (U16, U16) =>
    let res = av.i16().i32() * bv.i16().i32()
    ((res and 0xffff).u16(), (res >> 16).u16())
  end)

  fun ref op_div(a: U16, b: U16) => _mathEx(a, b, lambda(av: U16, bv: U16): (U16, U16) =>
    if av == 0 then (0, 0) else
      (bv / av, ((bv.u32() << 16) / av.u32()).u16())
    end
  end)

  fun ref op_dvi(a: U16, b: U16) => _mathEx(a, b, lambda(av: U16, bv: U16): (U16, U16) =>
    if av == 0 then (0, 0) else
      ((bv.i16() / av.i16()).u16(), ((bv.i16().i32() << 16) / av.i16().i32()).u16())
    end
  end)

  fun ref op_mod(a: U16, b: U16) => _math(a, b, lambda(av: U16, bv: U16): U16 =>
    if av == 0 then 0 else bv % av end
  end)

  fun ref op_mdi(a: U16, b: U16) => _math(a, b, lambda(av: U16, bv: U16): U16 =>
    if av == 0 then 0 else (bv.i16() / av.i16()).u16() end
  end)

  fun ref op_and(a: U16, b: U16) => _math(a, b, lambda(av: U16, bv: U16): U16 =>
    av and bv
  end)
  fun ref op_bor(a: U16, b: U16) => _math(a, b, lambda(av: U16, bv: U16): U16 =>
    av or bv
  end)
  fun ref op_xor(a: U16, b: U16) => _math(a, b, lambda(av: U16, bv: U16): U16 =>
    av xor bv
  end)

  fun ref op_shr(a: U16, b: U16) => _mathEx(a, b, lambda(av: U16, bv: U16): (U16, U16) =>
    (bv >> av, ((bv.u32() << 16) >> av.u32()).u16())
  end)
  fun ref op_asr(a: U16, b: U16) => _mathEx(a, b, lambda(av: U16, bv: U16): (U16, U16) =>
    ((bv.i16() >> av.i16()).u16(), ((bv.i16().i32() << 16) >> av.u32().i32()).u16())
  end)
  fun ref op_shl(a: U16, b: U16) => _mathEx(a, b, lambda(av: U16, bv: U16): (U16, U16) =>
    (bv << av, ((bv.u32() << av.u32()) >> 16).u16())
  end)

  fun ref _branch(a: U16, b: U16, op: {(U16, U16): Bool} val) =>
    let av = readArg(a)
    let bv = readArg(b)
    skipping = not op(av, bv)

  fun ref op_ifb(a: U16, b: U16) => _branch(a, b, lambda(av: U16, bv: U16): Bool =>
    (av and bv) != 0
  end)
  fun ref op_ifc(a: U16, b: U16) => _branch(a, b, lambda(av: U16, bv: U16): Bool =>
    (av and bv) == 0
  end)
  fun ref op_ife(a: U16, b: U16) => _branch(a, b, lambda(av: U16, bv: U16): Bool =>
    av == bv
  end)
  fun ref op_ifn(a: U16, b: U16) => _branch(a, b, lambda(av: U16, bv: U16): Bool =>
    av != bv
  end)
  fun ref op_ifg(a: U16, b: U16) => _branch(a, b, lambda(av: U16, bv: U16): Bool =>
    bv > av
  end)
  fun ref op_ifa(a: U16, b: U16) => _branch(a, b, lambda(av: U16, bv: U16): Bool =>
    bv.i16() > av.i16()
  end)
  fun ref op_ifl(a: U16, b: U16) => _branch(a, b, lambda(av: U16, bv: U16): Bool =>
    bv < av
  end)
  fun ref op_ifu(a: U16, b: U16) => _branch(a, b, lambda(av: U16, bv: U16): Bool =>
    bv.i16() < av.i16()
  end)


  fun ref op_adx(a: U16, b: U16) =>
    let av = readArg(a)
    let bv = readArg(b, false)
    let res = bv.u32() + av.u32() + ex.u32()
    writeArg(b, res.u16())
    ex = if res > 0xffff then 1 else 0 end

  // TODO: Double-check these two are correct, especially SBX.
  fun ref op_sbx(a: U16, b: U16) =>
    let av = readArg(a)
    let bv = readArg(b, false)
    let res = ((0x10000 or bv.u32()) - av.u32()) + ex.u32()
    writeArg(b, res.u16())
    ex = if (res and 0xffff0000) == 0 then 0 else 0xffff end

  fun ref op_sti(a: U16, b: U16) =>
    writeArg(b, readArg(a))
    try
      regs(6) = regs(6) + 1
      regs(7) = regs(7) + 1
    end

  fun ref op_std(a: U16, b: U16) =>
    writeArg(b, readArg(a))
    try
      regs(6) = regs(6) - 1
      regs(7) = regs(7) - 1
    end


  // Special opcodes
  fun ref op_jsr(a: U16) =>
    push(pc)
    pc = readArg(a)

  fun ref op_int(a: U16) =>
    // Queue up the given interrupt.
    _intQueue.push(readArg(a))

  fun ref op_iag(a: U16) => writeArg(a, ia)
  fun ref op_ias(a: U16) => ia = readArg(a)

  fun ref op_rfi(a: U16) =>
    readArg(a) // Throw away the value.
    _intQueueing = false
    try regs(0) = pop() end
    pc = pop()

  fun ref op_iaq(a: U16) =>
    _intQueueing = readArg(a) == 0

  // TODO: Implement these three properly, once hardware is supported.
  fun ref op_hwn(a: U16) =>
    writeArg(a, 0)

  fun ref op_hwq(a: U16) =>
    let index = readArg(a)
    try
      regs(0) = 0
      regs(1) = 0
      regs(2) = 0
      regs(3) = 0
      regs(4) = 0
    end

  fun ref op_hwi(a: U16) =>
    readArg(a)


