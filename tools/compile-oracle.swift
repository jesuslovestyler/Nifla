// Nifla — Stone 53 proof harness: the compiler oracle.
//
// A small Swift main that links the untouched toolchain
// lexer, parser, interpreter, bare compiler, checker and
// compiler (src/Lexer.swift, src/Parser.swift,
// src/Interpreter.swift, src/BareCompiler.swift,
// src/Checker.swift, src/Compiler.swift — plus
// src/BareCompilerARM.swift, which the link pulls in:
// Compiler.swift reaches the ARM bare compiler) and
// reports the compiled door's work on a source file, in
// exactly the form selfhost/nifla-front.nifla's compile
// mode reports it:
//
//     compile     the hosted picture, as compileMain in
//                 src/Compiler.swift walks it for a
//                 hosted build: lex, parse, check (the
//                 checker with forBareMetal false,
//                 forGuest false), then translate with
//                 SwiftTranslator, the source named by
//                 the file's last path component.
//
// The verdict dump: an accepted program prints the
// generated Swift on stdout, byte for byte as
// SwiftTranslator gives it (the text ends with one
// newline), and leaves 0. A lex, parse or check refusal
// prints nothing on stdout, "Line N: <message>" on
// stderr, and leaves 1. A file that can't be read as
// UTF-8 prints a plain message on stderr and leaves 2;
// that wording (the front oracle's file-error wording)
// is not part of the identity claim the compile proofs
// prove.
//
// This file is a proof harness only — it is not part of
// the toolchain and nothing in src/ depends on it.
//
// Part of Nifla, a public-domain programming language
// by Tyler Kovalevich. See the Unlicense in the LICENSE
// file at the root of this repository.

import Foundation

@main
struct CompileOracle {
    static func main() {
        let args = CommandLine.arguments
        guard args.count >= 3, args[1] == "compile" else {
            FileHandle.standardError.write(Data("usage: compile-oracle compile <path>\n".utf8))
            exit(2)
        }
        let path = args[2]
        let source: String
        do {
            source = try String(contentsOfFile: path, encoding: .utf8)
        } catch {
            FileHandle.standardError.write(Data("I couldn't open the file '\(path)'. Check the name and the folder, and try again.\n".utf8))
            exit(2)
        }
        do {
            let tokens = try Lexer(source).tokenize()
            let program = try Parser(tokens).parseProgram()
            try Checker(program: program, forBareMetal: false, forGuest: false).check(program)
            var translator = SwiftTranslator()
            let generated = translator.translate(program, sourceName: URL(fileURLWithPath: path).lastPathComponent)
            FileHandle.standardOutput.write(Data(generated.utf8))
        } catch let error as NiflaError {
            FileHandle.standardError.write(Data((error.spoken + "\n").utf8))
            exit(1)
        } catch {
            FileHandle.standardError.write(Data("\(error)\n".utf8))
            exit(1)
        }
    }
}
