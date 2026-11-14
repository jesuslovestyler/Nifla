// Nifla — Stone 1 interpreter: the entry point.
//
// Usage:
//   nifla program.nifla    run a Nifla program from a file
//   nifla                  read a Nifla program from standard input
//
// A problem in the program is reported in plain words with its line
// number, and the exit code is 1. A program that runs cleanly exits 0.

import Foundation

func reportAndExit(_ text: String, code: Int32) -> Never {
    FileHandle.standardError.write(Data((text + "\n").utf8))
    exit(code)
}

let arguments = CommandLine.arguments
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
    try Interpreter().run(program)
} catch let error as NiflaError {
    reportAndExit(error.spoken, code: 1)
}
