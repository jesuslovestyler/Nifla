// Nifla — Stone 50 proof harness: the checker oracle.
//
// A small Swift main that links the untouched toolchain
// lexer, parser, interpreter, bare compiler and checker
// (src/Lexer.swift, src/Parser.swift, src/Interpreter.swift,
// src/BareCompiler.swift, src/Checker.swift — plus
// src/Compiler.swift and src/BareCompilerARM.swift, which
// the link pulls in: the bare compiler reaches
// findAssembler in Compiler.swift, and Compiler.swift
// reaches the ARM bare compiler) and reports the
// checker's verdict on a source file, in exactly the form
// selfhost/nifla-front.nifla's check modes report it:
//
//     check       the hosted picture (Checker forBareMetal
//                 false, forGuest false, as src/main.swift
//                 invokes it)
//     check-bare  the bare-metal picture (forBareMetal true,
//                 forGuest false, as src/Compiler.swift
//                 invokes it for a bare build)
//     check-guest the bare guest picture (forBareMetal true,
//                 forGuest true, as src/Compiler.swift
//                 invokes it for a bare guest build)
//
// The verdict dump: an accepted program prints exactly
// "checked" on stdout and leaves 0. A lex, parse or check
// refusal prints nothing on stdout, "Line N: <message>" on
// stderr, and leaves 1. A file that can't be read as UTF-8
// prints a plain message on stderr and leaves 2; that
// wording (the front oracle's file-error wording) is not
// part of the identity claim the check proofs prove.
//
// This file is a proof harness only — it is not part of the
// toolchain and nothing in src/ depends on it.
//
// Part of Nifla, a public-domain programming language by Tyler
// Kovalevich. See the Unlicense in the LICENSE file at the root
// of this repository.

import Foundation

@main
struct CheckOracle {
    static func main() {
        let args = CommandLine.arguments
        guard args.count >= 3, args[1] == "check" || args[1] == "check-bare" || args[1] == "check-guest" else {
            FileHandle.standardError.write(Data("usage: check-oracle check|check-bare|check-guest <path>\n".utf8))
            exit(2)
        }
        let mode = args[1]
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
            let bare = mode != "check"
            let guest = mode == "check-guest"
            try Checker(program: program, forBareMetal: bare, forGuest: guest).check(program)
            print("checked")
        } catch let error as NiflaError {
            FileHandle.standardError.write(Data((error.spoken + "\n").utf8))
            exit(1)
        } catch {
            FileHandle.standardError.write(Data("\(error)\n".utf8))
            exit(1)
        }
    }
}
