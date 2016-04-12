use ".."

use "files"
use "time"

use "debug"

type PendingOp is (Bool, U16, U16, U16)

// Implements the HMD2043 disk drive spec.
// Supports both synchronous and asynchronous ("non-blocking") modes.
// Currently the disk is selected using -d <disk file> on the command line.
// Also currently, the number and size of sectors is not constrained - the file
// can be any size.
// Interrupt 1 that queries the size uses 1KB = 512 word sectors, and rounds the
// file size up to a maximum of 0xffff sectors.
// TODO: Support hot-swapping disks on an F-key or something.
actor HWDisk is Device
  let _cpu: CPU tag
  let _env: Env

  let _timers: Timers tag = Timers()

  let _file: (File | None)

  // Pending operations are encoded as (Write?, sector, count, address).
  var _pendingOperation: (None | PendingOp) = None
  var _doOperation: Bool = false

  var _nonBlocking: Bool = false
  var _message: U16 = 0

  var _lastError: U16 = 0
  var _lastInterruptType: U16 = 0

  var _lastSector: U16 = 0

  var _state: (CPUState iso | None) = None

  // TODO: Remove this, it's for debugging.
  let fmtWord: FormatSettingsInt = FormatSettingsInt.set_format(FormatHexBare)
      .set_width(4)
      .set_fill('0')


  new create(env: Env, cpu: CPU tag) =>
    _env = env
    _cpu = cpu

    // Look for a disk name in the arguments.
    _file = try
      if env.args(2) == "-d" then
        let filename = env.args(3)
        let caps = recover val FileCaps.set(FileRead).set(FileWrite).set(FileStat) end
        let fp = try FilePath(env.root as AmbientAuth, filename, caps) else
          env.out.print("Failed to locate disk file: '" + filename + "'")
          error
        end

        match CreateFile(fp)
        | let f: File =>
          Debug.err("DISK: Loaded file successfully")
          f
        end
      end
    end


  fun tag _notify(): TimerNotify iso^ =>
    object iso is TimerNotify
      let parent: HWDisk = this
      fun ref apply(timer: Timer, count: U64): Bool =>
        Debug.err("DISK: Raw disk timer fired")
        parent.timerExpired()
        false // Don't reschedule; disk timeouts are one-shot.
    end

  fun id(): U32 => 0x74fa4cae
  fun manufacturer(): U32 => 0x21544948
  fun version(): U16 => 0x07c2

  be hardwareInfo(st: CPUState iso) =>
    _cpu.run(injectHardwareInfo(consume st))

  // Called when the disk read/write timer expires.
  // There are two cases here: on an async operation, we need to wait for the
  // next CPU tick. On a non-async operation, we're actually still holding the
  // CPUState.
  be timerExpired() =>
    Debug.err("DISK: timerExpired()")
    match (_pendingOperation, _state = None)
    | (let op: PendingOp, let st: CPUState iso) =>
      Debug.err("DISK: Running async op")
      _cpu.run(_performOperation(op, consume st))
    | (None, let st: CPUState iso) =>
      Debug.err("DISK: Timer expired but no pending op")
      _cpu.run(consume st)
    | (_, None) => None // Bad state
    end

  be interrupt(st: CPUState iso) =>
    var shouldReturn = true
    try
      let msg = st.regs(0)
      Debug.err("DISK: Interrupt: " + msg.string())
      match msg
      | 0 => // QUERY_MEDIA_PRESENT Sets B to 1 when a disk is inserted, 0 if not.
        st.regs(1) = match _file | None => 0 else 1 end
        st.regs(0) = 0 // No error

      | 1 => // QUERY_MEDIA_PARAMETERS B = words per sector, C = sectors, X = 1
             // if write-locked, 0 otherwise.
        match _file
        | let f: File =>
          st.regs(0) = 0 // No error
          st.regs(1) = 512 // Hard-coded currently.
          st.regs(2) = ((f.size() + 511) / 512).u16()
          st.regs(3) = 0 // No support for write-protection right now.
        else
          st.regs(0) = 1 // ERROR_NO_MEDIA
        end

      | 2 => // QUERY_DEVICE_FLAGS
        // TODO: Add the media status interrupt flag here when it can change.
        st.regs(1) = if _nonBlocking then 1 else 0 end

      | 3 => // UPDATE_DEVICE_FLAGS
        // TODO: Add the media status interrupt flag here when it can change.
        _nonBlocking = (st.regs(1) and 0x01) > 0

      | 4 => // QUERY_INTERRUPT_TYPE
        st.regs(0) = _lastError
        st.regs(1) = _lastInterruptType

      | 5 => // SET_INTERRUPT_MESSAGE
        _message = st.regs(1)
        st.regs(0) = 0 // No error

      | 0x10 => // READ_SECTORS
        match _file
        | None =>
          Debug.err("DISK: READ_SECTORS received but no disk is loaded")
          st.regs(0) = 1 // ERROR_NO_MEDIA
        | let f: File =>
          match _pendingOperation
          | None =>
            Debug.err("DISK: READ_SECTORS is go")
            let start = st.regs(1)
            // TODO: Not checking if the requested sector exists in the file.
            // I'm not sure that's a useful check, actually.
            _pendingOperation = (false, start, st.regs(2), st.regs(3))
            _timeToSeek(start)
            shouldReturn = _nonBlocking
            st.regs(0) = 0 // No error
          else
            // An operation is already in progress!
            Debug.err("DISK: READ_SECTORS aborted, another operation is already pending")
            st.regs(0) = 3 // ERROR_PENDING
          end
        end

      | 0x11 => // WRITE_SECTORS
        match _file
        | None =>
          Debug.err("DISK: WRITE_SECTORS received but no disk is loaded")
          st.regs(0) = 1 // ERROR_NO_MEDIA
        | let f: File =>
          match _pendingOperation
          | None =>
            Debug.err("DISK: WRITE_SECTORS is go")
            let start = st.regs(1)
            // TODO: Not checking if the requested sector exists in the file.
            // I'm not sure that's a useful check, actually.
            _pendingOperation = (true, start, st.regs(2), st.regs(3))
            _timeToSeek(start)
            shouldReturn = _nonBlocking
            st.regs(0) = 0 // No error
          else
            // An operation is already in progress!
            Debug.err("DISK: WRITE_SECTORS aborted, another operation is already pending")
            st.regs(0) = 3 // ERROR_PENDING
          end
        end

      | 0xffff => // QUERY_MEDIA_QUALITY
        match _file
        | None => st.regs(0) = 1 // ERROR_NO_MEDIA
        else
          st.regs(0) = 0
          st.regs(1) = 0x7fff // Always claim to be a HIT
        end
      end
    end

    if shouldReturn then
      _cpu.run(consume st)
    else
      _state = consume st
    end


  fun ref _performOperation(op: PendingOp, st: CPUState iso): CPUState iso^ =>
    (let isWrite: Bool, let start: U16, let count: U16, let address: U16) = op
    Debug.err("DISK: Performing a " + (if isWrite then "write" else "read" end)
        + " at sector " + start.string() + " of length " + count.string()
        + " at address " + address.string(fmtWord))
    try
      _doOperation = false
      match _file
      | let f: File =>
        Debug.err("DISK: File is available, performing operation.")
        if isWrite then
          var tmp = Array[U8](count.usize() * 1024)
          var i: USize = 0
          let max = (count.usize() * 512)
          while i < max do
            // Big-endian, same as the binaries.
            let x = st.mem(address.usize() + i)
            tmp.push((x >> 8).u8())
            tmp.push((x and 0xff).u8())
            i = i + 1
          end

          Debug.err("DISK: File writeable: " + f.writeable.string())

          f.seek_start(start.usize() * 1024)
          let res = f.write(tmp)
          f.flush()

          Debug.err("DISK: write() returned " + res.string())
          Debug.err("DISK: File written out")

          _lastInterruptType = 3 // WRITE_COMPLETE
          if _nonBlocking then
            _cpu.triggerInterrupt(_message)
          end
          Debug.err("DISK: Bottom of write")
        else
          f.seek_start(start.usize() * 1024)
          let tmp = f.read(count.usize() * 1024)
          Debug.err("DISK: Read " + tmp.size().string() + " bytes from the file")
          var i: USize = 0
          let max = (count.usize() * 512).min(tmp.size() / 2)
          while i < max do
            let x = (tmp(i * 2).u16() << 8) or (tmp((i * 2) + 1).u16())
            st.mem(address.usize() + i) = x
            i = i + 1
          end

          Debug.err("DISK: Done reading.")
          _lastInterruptType = 2 // READ_COMPLETE
          if _nonBlocking then
            _cpu.triggerInterrupt(_message)
          end
        end

        _lastSector = start + count
        _lastError = 0 // No error
      end
    end
    consume st


  be tick(index: USize, st: CPUState iso) =>
    // Normally nothing, unless _doOperation is set.
    // That flag is set by an async operation's timer expiring, since we can't
    // process the result without the CPUState.
    if _doOperation then
      _doOperation = false
      match _pendingOperation = None
      | let op: PendingOp =>
        let st' = _performOperation(op, consume st)
        _cpu.hardwareDone(index, consume st')
      else
        _cpu.hardwareDone(index, consume st)
      end
    else
      _cpu.hardwareDone(index, consume st)
    end


  // Determines the time required to seek to the requested sector.
  // Spawns a timer to call me back when it's complete.
  // NB: The time might be 0, if the needed sector is next up.
  fun ref _timeToSeek(sector: U16) =>
    let diff = (_lastSector - sector).abs()
    let deltaTracks: U16 = diff / 18 // 18 sectors per track.
    // 80 sectors means a full stroke across 79 sectors takes 200ms = 200M ns
    let time: U64 = (deltaTracks.u64() * 200000000) / 79
    Debug.err("DISK: Seek time between " + _lastSector.string() + " and " +
        sector.string() + " is " + time.string() + "ns")
    _timers(Timer(_notify(), time))

  be dispose() =>
    _timers.dispose()
    match _file
    | let f: File =>
      f.dispose()
    end

