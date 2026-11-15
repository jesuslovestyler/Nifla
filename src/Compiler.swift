// Nifla — Stone 5: the compiler (first form).
//
// niflac reads a Nifla program, runs the checker over it, and —
// when the checker is content — translates the program into Swift
// and compiles that Swift, together with the small runtime in
// runtime/NiflaRuntime.swift, into a native program. The generated
// Swift works through the runtime's values for everything, so a
// compiled program behaves exactly as the interpreter would have
// run it: same output, same plain-words errors, same guards. The
// gain is that it stands alone — no interpreter involved.
//
// The translation mirrors the interpreter's own order of work at
// every step (a call's function is looked up before its values are
// worked out; a field's object is checked before the new value is
// worked out; and so on), because the words of an error, and which
// error comes first, are part of the language.

import Foundation

// Translates a parsed program into Swift source: a header, the
// translated statements inside a do/catch that reports a NiflaError
// the same way the interpreter's entry point does, and nothing
// else — the runtime file carries the rest.
struct SwiftTranslator {
    private var lines: [String] = []
    private var counter = 0

    // The floor blocks (Stone 7) this program holds, in the order
    // the translation meets them. Each becomes a small assembly
    // function, nifla_floor_0, nifla_floor_1, ..., assembled and
    // linked into the compiled program; the generated Swift calls
    // them by those names.
    private(set) var floorBlocks: [String] = []

    private mutating func fresh(_ prefix: String) -> String {
        counter += 1
        return "__\(prefix)\(counter)"
    }

    mutating func translate(_ program: [Stmt], sourceName: String) -> String {
        lines.append("// Translated from \(sourceName) by niflac (Nifla Stone 5).")
        lines.append("// This file was made by a program; the Nifla source is the one to read and change.")
        lines.append("import Foundation")
        lines.append("")
        lines.append("let __m = Machine()")
        lines.append("let __top = Scope()")
        lines.append("do {")
        translateBlock(program, scope: "__top", inFunction: false, indent: "    ")
        lines.append("} catch let error as NiflaError {")
        lines.append("    FileHandle.standardError.write(Data((error.spoken + \"\\n\").utf8))")
        lines.append("    exit(1)")
        lines.append("}")
        if !floorBlocks.isEmpty {
            lines.append("")
            lines.append("// The floor blocks (Stones 7 and 9): raw processor")
            lines.append("// instructions, assembled separately and linked into")
            lines.append("// this program. Each is called through the runtime's")
            lines.append("// desk (Machine.runFloor): the handed numbers, the one")
            lines.append("// block of bytes, and the results area are laid out")
            lines.append("// for its instructions, which give back the number")
            lines.append("// left in the processor's return register (rax).")
            for index in floorBlocks.indices {
                lines.append("@_silgen_name(\"nifla_floor_\(index)\")")
                lines.append("func __floor\(index)(_ inputs: UnsafePointer<Int64>?, _ inputCount: Int64, _ memory: UnsafeMutablePointer<UInt8>?, _ memoryCount: Int64, _ results: UnsafeMutablePointer<Int64>, _ resultCount: UnsafeMutablePointer<Int64>) -> Int64")
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private mutating func emit(_ indent: String, _ text: String) {
        lines.append(indent + text)
    }

    private mutating func translateBlock(_ statements: [Stmt], scope: String, inFunction: Bool, indent: String) {
        for statement in statements {
            translateStatement(statement, scope: scope, inFunction: inFunction, indent: indent)
        }
    }

    // A block that runs in a fresh child scope: returns the child
    // scope's generated name.
    private mutating func childScope(of parent: String, indent: String) -> String {
        let name = fresh("s")
        emit(indent, "let \(name) = Scope(parent: \(parent))")
        return name
    }

    private mutating func translateStatement(_ statement: Stmt, scope: String, inFunction: Bool, indent: String) {
        switch statement {
        case .declare(let name, let kindWord, let valueExpr, let line):
            emit(indent, "try __m.checkDeclare(\(swiftText(name)), in: \(scope), line: \(line))")
            if let kindWord {
                // Stone 18: an annotated 'let' — the value is
                // checked against the annotation before the
                // variable exists, and the annotation is
                // remembered for every later setting of it.
                let value = fresh("v")
                emit(indent, "let \(value) = \(genExpr(valueExpr, scope: scope))")
                emit(indent, "try __m.checkAnnotation(name: \(swiftText(name)), kindWord: \(swiftText(kindWord)), value: \(value), line: \(line))")
                emit(indent, "\(scope).declare(\(swiftText(name)), \(value))")
                emit(indent, "\(scope).declareAnnotation(\(swiftText(name)), \(swiftText(kindWord)))")
            } else {
                emit(indent, "\(scope).declare(\(swiftText(name)), \(genExpr(valueExpr, scope: scope)))")
            }

        case .assign(let name, let valueExpr, let line):
            emit(indent, "try __m.assign(\(swiftText(name)), \(genExpr(valueExpr, scope: scope)), in: \(scope), line: \(line))")

        case .assignTarget(let target, let valueExpr, let line):
            switch target {
            case .field(let baseExpr, let fieldName, _):
                let base = fresh("b")
                let object = fresh("o")
                emit(indent, "let \(base) = \(genExpr(baseExpr, scope: scope))")
                emit(indent, "let \(object) = try __m.fieldTarget(\(base), \(swiftText(fieldName)), line: \(line))")
                emit(indent, "\(object).set(\(swiftText(fieldName)), \(genExpr(valueExpr, scope: scope)))")
            case .index(let baseExpr, let indexExpr, let indexLine):
                let base = fresh("b")
                let slot = fresh("t")
                emit(indent, "let \(base) = \(genExpr(baseExpr, scope: scope))")
                emit(indent, "let \(slot) = try __m.indexTarget(\(base), \(genExpr(indexExpr, scope: scope)), line: \(indexLine))")
                emit(indent, "try \(slot).set(\(genExpr(valueExpr, scope: scope)))")
            default:
                break
            }

        case .say(let valueExpr, _):
            emit(indent, "__m.say(\(genExpr(valueExpr, scope: scope)))")

        case .ifElse(let condition, let thenBlock, let elseBlock, let line):
            emit(indent, "if try __m.decide(\(genExpr(condition, scope: scope)), kind: \"if\", line: \(line)) {")
            let thenScope = childScope(of: scope, indent: indent + "    ")
            translateBlock(thenBlock, scope: thenScope, inFunction: inFunction, indent: indent + "    ")
            if let elseBlock {
                emit(indent, "} else {")
                let elseScope = childScope(of: scope, indent: indent + "    ")
                translateBlock(elseBlock, scope: elseScope, inFunction: inFunction, indent: indent + "    ")
            }
            emit(indent, "}")

        case .whileLoop(let condition, let body, let line):
            emit(indent, "while true {")
            emit(indent + "    ", "guard try __m.decide(\(genExpr(condition, scope: scope)), kind: \"while\", line: \(line)) else { break }")
            emit(indent + "    ", "try __m.tickLoop(line: \(line))")
            let bodyScope = childScope(of: scope, indent: indent + "    ")
            translateBlock(body, scope: bodyScope, inFunction: inFunction, indent: indent + "    ")
            emit(indent, "}")

        case .repeatLoop(let countExpr, let body, let line):
            let count = fresh("n")
            let done = fresh("d")
            emit(indent, "let \(count) = try __m.repeatCount(\(genExpr(countExpr, scope: scope)), line: \(line))")
            emit(indent, "var \(done) = 0.0")
            emit(indent, "while \(done) < \(count) {")
            emit(indent + "    ", "try __m.tickLoop(line: \(line))")
            let bodyScope = childScope(of: scope, indent: indent + "    ")
            translateBlock(body, scope: bodyScope, inFunction: inFunction, indent: indent + "    ")
            emit(indent + "    ", "\(done) += 1")
            emit(indent, "}")

        case .forEach(let name, let overExpr, let body, let line):
            let items = fresh("xs")
            let pos = fresh("i")
            emit(indent, "let \(items) = try __m.forItems(\(genExpr(overExpr, scope: scope)), line: \(line))")
            emit(indent, "var \(pos) = 0")
            emit(indent, "while \(pos) < \(items).count {")
            emit(indent + "    ", "try __m.tickLoop(line: \(line))")
            let bodyScope = childScope(of: scope, indent: indent + "    ")
            emit(indent + "    ", "\(bodyScope).declare(\(swiftText(name)), \(items)[\(pos)])")
            translateBlock(body, scope: bodyScope, inFunction: inFunction, indent: indent + "    ")
            emit(indent + "    ", "\(pos) += 1")
            emit(indent, "}")

        case .define(let name, let params, let paramKinds, let returnKind, let body, let line):
            let paramList = params.map { swiftText($0) }.joined(separator: ", ")
            let kindList = paramKinds.map { $0.map { swiftText($0) } ?? "nil" }.joined(separator: ", ")
            let retKind = returnKind.map { swiftText($0) } ?? "nil"
            emit(indent, "try __m.define(\(swiftText(name)), params: [\(paramList)], paramKinds: [\(kindList)], returnKind: \(retKind), home: \(scope), line: \(line)) { __m, __call in")
            translateBlock(body, scope: "__call", inFunction: true, indent: indent + "    ")
            emit(indent, "}")

        case .give(let valueExpr, let line):
            if inFunction {
                emit(indent, "throw NiflaReturn(value: \(genExpr(valueExpr, scope: scope)), line: \(line))")
            } else {
                emit(indent, "try __m.giveOutside(line: \(line))")
            }

        case .attempt(let body, let recovery, _):
            // A Swift do/catch over NiflaError only: a 'give'
            // (NiflaReturn) thrown inside either block passes
            // straight through, as it does in the interpreter.
            // The caught problem's words are declared as the
            // variable 'problem' in the recovery block's scope.
            let errorName = fresh("e")
            emit(indent, "do {")
            let bodyScope = childScope(of: scope, indent: indent + "    ")
            translateBlock(body, scope: bodyScope, inFunction: inFunction, indent: indent + "    ")
            emit(indent, "} catch let \(errorName) as NiflaError {")
            let recoveryScope = childScope(of: scope, indent: indent + "    ")
            emit(indent + "    ", "\(recoveryScope).declare(\"problem\", Value.text(\(errorName).message))")
            translateBlock(recovery, scope: recoveryScope, inFunction: inFunction, indent: indent + "    ")
            emit(indent, "}")

        case .doCall(let name, let args, let line):
            emit(indent, "try __m.callStatement(\(swiftText(name)), args: [\(argClosures(args, scope: scope))], line: \(line))")

        case .doExpr(let expr, _):
            emit(indent, "_ = \(genExpr(expr, scope: scope))")
        }
    }

    // Call arguments are handed over as little closures, not values,
    // so the machine can look the function up before working any of
    // them out — the interpreter's order, and so the same error
    // comes first.
    private mutating func argClosures(_ args: [Expr], scope: String) -> String {
        args.map { "{ \(genExpr($0, scope: scope)) }" }.joined(separator: ", ")
    }

    private mutating func genExpr(_ expr: Expr, scope: String) -> String {
        switch expr {
        case .number(let value, _):
            return "Value.number(\(swiftNumber(value)))"
        case .text(let value, _):
            return "Value.text(\(swiftText(value)))"
        case .boolean(let value, _):
            return "Value.boolean(\(value))"
        case .nothing:
            return "Value.nothing"
        case .variable(let name, let line):
            return "try __m.lookup(\(swiftText(name)), in: \(scope), line: \(line))"
        case .call(let name, let args, let line):
            return "try __m.callValue(\(swiftText(name)), args: [\(argClosures(args, scope: scope))], line: \(line))"
        case .object(let fields, _):
            let parts = fields.map { "(\(swiftText($0.name)), \(genExpr($0.value, scope: scope)))" }
            return "__m.makeObject([\(parts.joined(separator: ", "))])"
        case .list(let items, _):
            let parts = items.map { genExpr($0, scope: scope) }
            return "__m.makeList([\(parts.joined(separator: ", "))])"
        case .field(let base, let name, let line):
            return "try __m.readField(\(genExpr(base, scope: scope)), \(swiftText(name)), line: \(line))"
        case .index(let base, let index, let line):
            return "try __m.readIndex(\(genExpr(base, scope: scope)), \(genExpr(index, scope: scope)), line: \(line))"
        case .floor(let asm, let args, let line):
            // A floor block becomes a call to its assembly function,
            // through the runtime's desk: the handed values are
            // worked out here, checked and laid out there, and the
            // block gives back its number — or a list, when it
            // wrote extra answers into the results area.
            let index = floorBlocks.count
            floorBlocks.append(asm)
            let values = args.map { genExpr($0, scope: scope) }.joined(separator: ", ")
            return "try __m.runFloor(args: [\(values)], line: \(line)) { __floor\(index)($0, $1, $2, $3, $4, $5) }"
        case .negate(let inner, let line):
            return "try __m.negate(\(genExpr(inner, scope: scope)), line: \(line))"
        case .binary(let left, let op, let right, let line):
            return "try __m.apply(\(swiftText(op)), \(genExpr(left, scope: scope)), \(genExpr(right, scope: scope)), line: \(line))"
        }
    }

    // A Double written so Swift reads back the very same value.
    private func swiftNumber(_ value: Double) -> String {
        if value == value.rounded() && abs(value) < 9.0e15 {
            return String(Int(value)) + ".0"
        }
        return String(value)
    }

    // A string written as a Swift string literal.
    private func swiftText(_ value: String) -> String {
        var out = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\t": out += "\\t"
            case "\r": out += "\\r"
            default:
                if scalar.value < 0x20 || scalar.value == 0x7F {
                    out += "\\u{\(String(scalar.value, radix: 16))}"
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        out += "\""
        return out
    }
}

// Finds the Swift compiler, the same places build.sh looks. (The
// home folder is read from the environment, as the shell reads it:
// NSHomeDirectory() can disagree with $HOME for some users.)
func findSwiftc() -> String? {
    let environment = ProcessInfo.processInfo.environment
    if let override = environment["SWIFTC"], !override.isEmpty {
        return override
    }
    let home = environment["HOME"] ?? NSHomeDirectory()
    let candidates = [
        "/usr/bin/swiftc",
        "/usr/local/bin/swiftc",
        "/opt/swift/usr/bin/swiftc",
        home + "/swift/usr/bin/swiftc",
        home + "/workspace/turtle-browser/harness-038/toolchain/swift-6.0.3-RELEASE-ubuntu24.04/usr/bin/swiftc",
    ]
    // PATH first, like build.sh.
    if let path = environment["PATH"] {
        for directory in path.split(separator: ":") {
            let candidate = String(directory) + "/swiftc"
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
    }
    for candidate in candidates {
        if FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }
    }
    return nil
}

// Finds the runtime file compiled programs carry, looking next to
// this program first, then in the folder the program is run from.
func findRuntime() -> String? {
    let environment = ProcessInfo.processInfo.environment
    if let override = environment["NIFLA_RUNTIME"], !override.isEmpty,
       FileManager.default.fileExists(atPath: override) {
        return override
    }
    let programDirectory = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().path
    let candidates = [
        programDirectory + "/runtime/NiflaRuntime.swift",
        programDirectory + "/../runtime/NiflaRuntime.swift",
        FileManager.default.currentDirectoryPath + "/runtime/NiflaRuntime.swift",
    ]
    for candidate in candidates {
        if FileManager.default.fileExists(atPath: candidate) {
            return candidate
        }
    }
    return nil
}

// The niflac entry point: check, then compile. Returns the exit
// code. Every refusal is plain words, and a refused program leaves
// no program behind.
func compileMain(arguments: [String]) -> Int32 {
    func fail(_ text: String, code: Int32) -> Int32 {
        FileHandle.standardError.write(Data((text + "\n").utf8))
        return code
    }

    var input: String? = nil
    var output: String? = nil
    var bare = false
    var guest = false
    var videoRequest: (width: Int, height: Int, depth: Int)? = nil
    var preludes: [String] = []
    var index = 1
    while index < arguments.count {
        let argument = arguments[index]
        if argument == "--bare" {
            bare = true
        } else if argument == "--guest" {
            guest = true
        } else if argument == "--video" {
            index += 1
            guard index < arguments.count else {
                return fail("The '--video' needs the mode it asks the loader for, written as WIDTHxHEIGHTxDEPTH, like: niflac --bare program.nifla --video 1024x768x32 -o program.elf", code: 2)
            }
            let parts = arguments[index].split(separator: "x")
            guard parts.count == 3,
                  let w = Int(parts[0]), let h = Int(parts[1]), let d = Int(parts[2]),
                  w > 0, h > 0, [8, 15, 16, 24, 32].contains(d) else {
                return fail("The '--video' mode '\(arguments[index])' isn't one I can ask for — write it as WIDTHxHEIGHTxDEPTH with a depth of 8, 15, 16, 24, or 32, like: --video 1024x768x32", code: 2)
            }
            videoRequest = (width: w, height: h, depth: d)
        } else if argument == "--prelude" {
            index += 1
            guard index < arguments.count else {
                return fail("The '--prelude' needs the name of a file of function definitions to lay under the program, like: niflac --bare main.nifla --prelude barelib/screen.nifla -o main.elf", code: 2)
            }
            preludes.append(arguments[index])
        } else if argument == "-o" {
            index += 1
            guard index < arguments.count else {
                return fail("The '-o' needs a name for the program to make, like: niflac hello.nifla -o hello", code: 2)
            }
            output = arguments[index]
        } else if input == nil {
            input = argument
        } else {
            return fail("I only need one program to compile. Give me one file, like: niflac examples/hello.nifla", code: 2)
        }
        index += 1
    }

    guard let inputPath = input else {
        return fail("Give me a Nifla program to compile, like: niflac examples/hello.nifla", code: 2)
    }

    let source: String
    do {
        source = try String(contentsOf: URL(fileURLWithPath: inputPath), encoding: .utf8)
    } catch {
        return fail("I couldn't open the file '\(inputPath)'. Check the name and the folder, and try again.", code: 2)
    }

    // Stone 15: a bare build may lay prelude files under the
    // program — libraries of function definitions (the screen
    // library is the first) whose makes become part of the
    // program, as if they stood at its top. A prelude may only
    // make functions; anything else in one is refused in plain
    // words. Preludes belong to the bare build, where there is
    // no other library mechanism yet.
    if !preludes.isEmpty && !bare {
        return fail("Preludes (--prelude) are part of the bare-metal build for now — add '--bare' to use one, like: niflac --bare main.nifla --prelude barelib/screen.nifla -o main.elf", code: 2)
    }
    // Stone 17: a guest is a kind of bare program — one that
    // is loaded and called by a host instead of booted — so
    // '--guest' only makes sense beside '--bare'.
    if guest && !bare {
        return fail("A guest is a bare-metal program that a host loads and calls instead of booting — add '--bare' to build one, like: niflac --bare --guest guest.nifla -o guest.bin", code: 2)
    }
    // The video request belongs to a booted bare program: it
    // is the loader who is asked, and only a host is booted.
    if videoRequest != nil && !bare {
        return fail("The '--video' request asks the loader for a graphics mode when a bare-metal program boots — add '--bare' to use it, like: niflac --bare program.nifla --video 1024x768x32 -o program.elf", code: 2)
    }
    if videoRequest != nil && guest {
        return fail("A guest is never booted by a loader, so there is no one to ask for a video mode — take '--video' out of the guest's build; the host owns the screen.", code: 2)
    }
    var preludeStatements: [Stmt] = []
    for preludePath in preludes {
        let preludeSource: String
        do {
            preludeSource = try String(contentsOf: URL(fileURLWithPath: preludePath), encoding: .utf8)
        } catch {
            return fail("I couldn't open the prelude file '\(preludePath)'. Check the name and the folder, and try again.", code: 2)
        }
        do {
            let preludeProgram = try Parser(try Lexer(preludeSource).tokenize()).parseProgram()
            for statement in preludeProgram {
                guard case .define = statement else {
                    return fail("The prelude '\(preludePath)' holds a line that isn't a function definition. A prelude may only make functions (make ...) — the program itself holds everything else.", code: 1)
                }
            }
            preludeStatements += preludeProgram
        } catch let error as NiflaError {
            return fail("In the prelude '\(preludePath)': \(error.spoken)", code: 1)
        } catch {
            return fail("Something went wrong while reading the prelude '\(preludePath)'.", code: 1)
        }
    }

    let program: [Stmt]
    do {
        let tokens = try Lexer(source).tokenize()
        program = preludeStatements + (try Parser(tokens).parseProgram())
        try Checker(program: program, forBareMetal: bare, forGuest: guest).check(program)
    } catch let error as NiflaError {
        return fail(error.spoken, code: 1)
    } catch {
        return fail("Something went wrong while reading the program.", code: 1)
    }

    // Stone 11: the bare-metal target has its own translator
    // and build (BareCompiler.swift) — no Swift runtime, no
    // hosted runtime file, nothing underneath the program.
    if bare {
        return compileBare(inputPath: inputPath, output: output, program: program, guestMode: guest, videoRequest: videoRequest, fail: fail)
    }

    guard let runtimePath = findRuntime() else {
        return fail("I couldn't find the runtime file (runtime/NiflaRuntime.swift) that compiled programs carry. Run niflac from the Nifla folder, or set NIFLA_RUNTIME to the file's path.", code: 2)
    }
    guard let swiftc = findSwiftc() else {
        return fail("I couldn't find a Swift compiler (swiftc), which niflac needs to build the program. Set SWIFTC to its path and try again.", code: 2)
    }

    let outputPath: String
    if let output {
        outputPath = output
    } else {
        let url = URL(fileURLWithPath: inputPath)
        if url.pathExtension == "nifla" {
            outputPath = url.deletingPathExtension().path
        } else if url.pathExtension.isEmpty {
            outputPath = inputPath + ".compiled"
        } else {
            outputPath = url.deletingPathExtension().path
        }
    }
    let generatedPath = outputPath + ".swift"

    var translator = SwiftTranslator()
    let generated = translator.translate(program, sourceName: URL(fileURLWithPath: inputPath).lastPathComponent)
    do {
        try generated.write(toFile: generatedPath, atomically: true, encoding: .utf8)
    } catch {
        return fail("I couldn't write the translated program to '\(generatedPath)'.", code: 2)
    }

    // Swift allows a program's own statements only in a file named
    // main.swift, so the compiler is handed a copy of the
    // translation under that name, in a scratch folder; the copy at
    // generatedPath stays for reading.
    let scratch = FileManager.default.temporaryDirectory
        .appendingPathComponent("niflac-\(ProcessInfo.processInfo.processIdentifier)")
    let scratchMain = scratch.appendingPathComponent("main.swift").path
    do {
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        try generated.write(toFile: scratchMain, atomically: true, encoding: .utf8)
    } catch {
        return fail("I couldn't set up a scratch folder to build in.", code: 2)
    }
    defer { try? FileManager.default.removeItem(at: scratch) }

    // Floor blocks (Stones 7 and 9): wrap each block's raw
    // instructions as an assembly function. The wrapper lays out
    // the desk before the block's own instructions — the handed
    // numbers in r10 (how many in r11), the one block of bytes in
    // rbx (how many in r12), the results area in r13, and r14 set
    // to zero for the block to say how many extra answers it
    // wrote there — and afterwards writes r14 where the runtime
    // reads it, restores the registers a called function must
    // preserve, and returns, so the value in rax when the
    // instructions finish is the block's headline number. The
    // assembly is kept beside the program, like the generated
    // Swift, for anyone who wants to read it.
    var floorObjectPath: String? = nil
    var generatedAsmPath: String? = nil
    if !translator.floorBlocks.isEmpty {
        var asm = "// The floor blocks of \(URL(fileURLWithPath: inputPath).lastPathComponent), wrapped by niflac (Nifla Stones 7 and 9).\n"
        asm += "// Each block's instructions stand between a desk-laying-out\n"
        asm += "// prologue and a tidying-up epilogue; what is in rax when the\n"
        asm += "// instructions finish is the number the block gives back.\n"
        asm += "// Floor code is written in Intel syntax — 'mov rax, 1' — the\n"
        asm += "// way processor instructions are most often written and read.\n"
        asm += "    .intel_syntax noprefix\n"
        for (index, block) in translator.floorBlocks.enumerated() {
            asm += "\n    .text\n    .globl nifla_floor_\(index)\n    .type nifla_floor_\(index), @function\nnifla_floor_\(index):\n"
            asm += "    push rbx\n    push r12\n    push r13\n    push r14\n    push r15\n"
            asm += "    mov r10, rdi\n    mov r11, rsi\n    mov rbx, rdx\n    mov r12, rcx\n    mov r13, r8\n    mov r15, r9\n    xor r14d, r14d\n"
            asm += block + "\n"
            asm += "__nifla_floor_\(index)_done:\n"
            asm += "    cmp r14, 8\n    jle __nifla_floor_\(index)_counted\n    mov r14, 8\n__nifla_floor_\(index)_counted:\n"
            asm += "    mov [r15], r14\n"
            asm += "    pop r15\n    pop r14\n    pop r13\n    pop r12\n    pop rbx\n"
            asm += "    ret\n"
        }
        let asmPath = outputPath + ".s"
        do {
            try asm.write(toFile: asmPath, atomically: true, encoding: .utf8)
        } catch {
            return fail("I couldn't write the floor assembly to '\(asmPath)'.", code: 2)
        }
        generatedAsmPath = asmPath

        guard let cc = findAssembler() else {
            return fail("This program has floor blocks, and I couldn't find an assembler (cc) to build them with. Install a C compiler toolchain and try again.", code: 2)
        }
        let scratchAsm = scratch.appendingPathComponent("floor.s").path
        let objectPath = scratch.appendingPathComponent("floor.o").path
        do {
            try asm.write(toFile: scratchAsm, atomically: true, encoding: .utf8)
        } catch {
            return fail("I couldn't set up a scratch folder to build in.", code: 2)
        }
        let assembler = Process()
        assembler.executableURL = URL(fileURLWithPath: cc)
        assembler.arguments = ["-c", scratchAsm, "-o", objectPath]
        let assemblerErrors = Pipe()
        assembler.standardError = assemblerErrors
        assembler.standardOutput = Pipe()
        do {
            try assembler.run()
        } catch {
            return fail("I couldn't start the assembler at '\(cc)'.", code: 2)
        }
        assembler.waitUntilExit()
        if assembler.terminationStatus != 0 {
            let assemblerWords = String(data: assemblerErrors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            return fail("The floor blocks in '\(inputPath)' couldn't be assembled. The instructions inside a floor block are the processor's own, and the assembler is the judge of them. What it said:\n\(assemblerWords)", code: 1)
        }
        floorObjectPath = objectPath
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: swiftc)
    process.arguments = [scratchMain, runtimePath] + (floorObjectPath.map { [$0] } ?? []) + ["-o", outputPath]
    let errorPipe = Pipe()
    process.standardError = errorPipe
    process.standardOutput = Pipe()
    do {
        try process.run()
    } catch {
        return fail("I couldn't start the Swift compiler at '\(swiftc)'.", code: 2)
    }
    process.waitUntilExit()
    if process.terminationStatus != 0 {
        let compilerWords = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        try? FileManager.default.removeItem(atPath: outputPath)
        return fail("I translated '\(inputPath)' but the Swift compiler couldn't build it. What it said:\n\(compilerWords)", code: 1)
    }

    print("Made \(outputPath) — a standalone program, compiled from \(inputPath).")
    print("The Swift it was made from is kept at \(generatedPath), if you'd like to read it.")
    if let generatedAsmPath {
        print("The floor assembly it was made from is kept at \(generatedAsmPath).")
    }
    return 0
}

// Finds the assembler for floor blocks: a C compiler driver (cc)
// on the PATH, which every Swift toolchain machine here has.
func findAssembler() -> String? {
    let environment = ProcessInfo.processInfo.environment
    if let override = environment["CC"], !override.isEmpty {
        return override
    }
    if let path = environment["PATH"] {
        for directory in path.split(separator: ":") {
            let candidate = String(directory) + "/cc"
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
    }
    return nil
}
