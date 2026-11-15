// Nifla — the entry point, for both of Stone 5's programs.
//
// This one file builds into two programs (build.sh makes both):
//
//   nifla program.nifla    check a Nifla program, then run it
//   nifla                  read a Nifla program from standard input
//   niflac program.nifla   check a Nifla program, then compile it
//                          into a standalone native program
//   niflac --bare program.nifla
//                          compile a bare-metal subset of Nifla
//                          into a binary that boots on its own
//                          (Stone 11; see BareCompiler.swift)
//
// Which program this is is decided by the name it was called by.
// Either way, the checker (Stone 5) reads the program first, and a
// problem it can prove is reported in plain words with its line
// number before anything runs or is built. A program that runs
// cleanly exits 0; a problem exits 1 (or 2 when a file or the
// compiler itself couldn't be reached).

import Foundation

func reportAndExit(_ text: String, code: Int32) -> Never {
    FileHandle.standardError.write(Data((text + "\n").utf8))
    exit(code)
}

let arguments = CommandLine.arguments

if URL(fileURLWithPath: arguments[0]).lastPathComponent == "niflac" {
    exit(compileMain(arguments: arguments))
}

var source: String

if arguments.count > 1 {
    let path = arguments[1]
    do {
        source = try String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8)
    } catch {
        reportAndExit("I couldn't open the file '\(path)'. Check the name and the folder, and try again.", code: 2)
    }
} else {
    let data = FileHandle.standardInput.readDataToEndOfFile()
    source = String(data: data, encoding: .utf8) ?? ""
}

do {
    let tokens = try Lexer(source).tokenize()
    let program = try Parser(tokens).parseProgram()
    try Checker(program: program).check(program)
    // Floor code (Stone 7) runs only in a compiled program; the
    // interpreter refuses a program that holds any, before
    // anything runs.
    if let floorLine = firstFloorLine(in: program) {
        throw NiflaError(line: floorLine, message: floorRefusalMessage)
    }
    let interpreter = Interpreter()
    // The program's own arguments (Stone 6): the words after the
    // program's file name, which arguments() hands to the program.
    if arguments.count > 1 {
        interpreter.programArguments = Array(arguments.dropFirst(2))
    }
    try interpreter.run(program)
} catch let error as NiflaError {
    reportAndExit(error.spoken, code: 1)
}
