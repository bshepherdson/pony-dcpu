use "files"

actor Main
  new create(env: Env) =>
    let caps = recover val FileCaps.set(FileRead).set(FileStat) end

    let binary = try env.args(1) else
      env.out.print("Usage: ./dcpu <binary>")
      return
    end

    let fp = try FilePath(env.root, binary, caps) else
      env.out.print("Failed to locate binary file: '" + binary + "'")
      return
    end

    let dcpu = CPU.fromFile(env, fp)
