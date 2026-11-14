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
        case .declare(let name, let valueExpr, let line):
            emit(indent, "try __m.checkDeclare(\(swiftText(name)), in: \(scope), line: \(line))")
            emit(indent, "\(scope).declare(\(swiftText(name)), \(genExpr(valueExpr, scope: scope)))")

        case .assign(let name, let valueExpr, let line):
            emit(indent, "try __m.assign(\(swiftText(name)), \(genExpr(valueExpr, scope: scope)), in: \(scope), line: \(line))")

        case .assignField(let target, let valueExpr, let line):
            guard case .field(let baseExpr, let fieldName, _) = target else { return }
            let base = fresh("b")
            let object = fresh("o")
            emit(indent, "let \(base) = \(genExpr(baseExpr, scope: scope))")
            emit(indent, "let \(object) = try __m.fieldTarget(\(base), \(swiftText(fieldName)), line: \(line))")
            emit(indent, "\(object).set(\(swiftText(fieldName)), \(genExpr(valueExpr, scope: scope)))")

        case .say(let valueExpr, _):
            emit(indent, "print(\(genExpr(valueExpr, scope: scope)).spoken)")

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

        case .define(let name, let params, let body, let line):
            let paramList = params.map { swiftText($0) }.joined(separator: ", ")
            emit(indent, "try __m.define(\(swiftText(name)), params: [\(paramList)], home: \(scope), line: \(line)) { __m, __call in")
            translateBlock(body, scope: "__call", inFunction: true, indent: indent + "    ")
            emit(indent, "}")

        case .give(let valueExpr, let line):
            if inFunction {
                emit(indent, "throw NiflaReturn(value: \(genExpr(valueExpr, scope: scope)))")
            } else {
                emit(indent, "try __m.giveOutside(line: \(line))")
            }

        case .doCall(let name, let args, let line):
            emit(indent, "try __m.callStatement(\(swiftText(name)), args: [\(argClosures(args, scope: scope))], line: \(line))")
        }
    }

    // Call arguments are handed over as little closures, not values,
    // so the machine can look the function up before working any of
    // them out — the interpreter's order, and so the same error
    // comes first.
    private func argClosures(_ args: [Expr], scope: String) -> String {
        args.map { "{ \(genExpr($0, scope: scope)) }" }.joined(separator: ", ")
    }

    private func genExpr(_ expr: Expr, scope: String) -> String {
        switch expr {
        case .number(let value, _):
            return "Value.number(\(swiftNumber(value)))"
        case .text(let value, _):
            return "Value.text(\(swiftText(value)))"
        case .boolean(let value, _):
            return "Value.boolean(\(value))"
        case .variable(let name, let line):
            return "try __m.lookup(\(swiftText(name)), in: \(scope), line: \(line))"
        case .call(let name, let args, let line):
            return "try __m.callValue(\(swiftText(name)), args: [\(argClosures(args, scope: scope))], line: \(line))"
        case .object(let fields, _):
            let parts = fields.map { "(\(swiftText($0.name)), \(genExpr($0.value, scope: scope)))" }
            return "__m.makeObject([\(parts.joined(separator: ", "))])"
        case .field(let base, let name, let line):
            return "try __m.readField(\(genExpr(base, scope: scope)), \(swiftText(name)), line: \(line))"
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
    var index = 1
    while index < arguments.count {
        let argument = arguments[index]
        if argument == "-o" {
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

    let program: [Stmt]
    do {
        let tokens = try Lexer(source).tokenize()
        program = try Parser(tokens).parseProgram()
        try Checker(program: program).check(program)
    } catch let error as NiflaError {
        return fail(error.spoken, code: 1)
    } catch {
        return fail("Something went wrong while reading the program.", code: 1)
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

    let process = Process()
    process.executableURL = URL(fileURLWithPath: swiftc)
    process.arguments = [scratchMain, runtimePath, "-o", outputPath]
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
    return 0
}
