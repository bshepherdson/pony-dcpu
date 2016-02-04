use "files"

class CPU
  var mem: Array[U16] = Array[U16].init(where from = 0, len = 0x10000)
  var regs: Array[U16] = Array[U16].init(where from = 0, len = 8)
  var pc: U16 = 0
  var ex: U16 = 0
  var sp: U16 = 0
  var ia: U16 = 0

  let _env: Env

  new fromFile(env: Env, file: FilePath) =>
    _env = env
    try 
    let maybeFile = OpenFile(file)
    match maybeFile
    | FileErrNo => _env.out.print("Busted")
    else
      _env.out.print("Working")
    end



actor Main
  new create(env: Env) =>
    let caps = recover val FileCaps.set(FileRead).set(FileStat) end

    env.out.print("Hello, DCPU!")
