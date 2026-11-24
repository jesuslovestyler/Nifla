// Nifla — Stone 55 proof harness: the bare oracle.
//
// A small Swift main that links the untouched toolchain
// lexer, parser, interpreter, bare compiler, checker and
// compiler (src/Lexer.swift, src/Parser.swift,
// src/Interpreter.swift, src/BareCompiler.swift,
// src/Checker.swift, src/Compiler.swift — plus
// src/BareCompilerARM.swift, which the link pulls in:
// Compiler.swift reaches the ARM bare compiler) and
// reports the bare door's validation work on a source
// file, in exactly the form selfhost/nifla-front.nifla's
// barevalid modes report it:
//
//     barevalid         the host picture, as compileMain
//                       in src/Compiler.swift walks it for
//                       a bare build: lex, parse, check
//                       (the checker with forBareMetal
//                       true, forGuest false), then the
//                       bare validator (BareValidator in
//                       src/BareCompiler.swift) with
//                       guestMode false.
//     barevalid-guest   the guest picture: the checker
//                       with forGuest true, then the
//                       validator with guestMode true.
//     barecompile       the host picture walked the
//                       whole way: lex, parse, check,
//                       validate, then the bare translator
//                       (BareTranslator in
//                       src/BareCompiler.swift) made from
//                       that validator, printing the
//                       emitted assembly exactly as
//                       translate writes it — the form
//                       compileBare writes to the .s file
//                       beside the binary. The translator
//                       is made with no video request, as
//                       a build without the flag is.
//     barecompile-guest the guest picture walked the
//                       whole way, the translator's
//                       guestMode true.
//     card              featherCard (the same file)
//                       for the file's own bytes: the
//                       name from the file's name
//                       without its ending, the byte
//                       count, the FNV-1a-64 checksum
//                       — printed exactly as the card
//                       stands at a feather's head.
//                       The file is read as bytes and
//                       never lexed.
//     barecompile-arm   Stone 59: the ARM target's
//                       whole road, as compileMain in
//                       src/Compiler.swift walks it for
//                       a '--bare --arm' build: lex,
//                       parse, check (the checker with
//                       forBareMetal true, forGuest
//                       false), then compileBareARM in
//                       src/BareCompilerARM.swift —
//                       the bare validator (guestMode
//                       false), the target's own
//                       refusal walk, then the ARM
//                       translator (BareTranslatorARM),
//                       printing the emitted assembly
//                       exactly as the build writes it
//                       to the .s file beside the binary.
//                       The translator is made with no
//                       video request, as a build
//                       without the flag is.
//
// Stone 59's note on the ARM mode's shape: the
// target's refusal walk (armRefusal) is private to
// src/BareCompilerARM.swift, and compileBareARM is
// the only road to it — so this mode drives the real
// build itself, with a fail closure that records the
// driver's own words, and takes the assembly from
// the .s file the driver itself writes. Everything
// past that write — finding clang and ld.lld,
// assembling, linking, the driver's "Made ..." lines
// (stdout is sent to a scratch file while the build
// runs) — is driver machinery, outside the claim, as
// compileBare's driver half stood outside Stone
// 56's. A refusal the build speaks before the write
// (validation, or the target's own) is reported on
// stderr with the build's parting number, 1.
//
// The verdict dump: a program the whole road accepts
// prints exactly "valid" on stdout and leaves 0 in the
// barevalid modes, and the emitted assembly in the
// barecompile mode. A lex, parse, check or validation
// refusal prints nothing on stdout, "Line N: <message>"
// on stderr, and leaves 1. A file that can't be read
// as UTF-8 prints a plain message on stderr and leaves
// 2; that wording (the front oracle's file-error
// wording) is not part of the identity claim the bare
// proofs prove.
//
// Stone 55's claim was the validator's verdict; Stone
// 56 grows this oracle the barecompile mode, and the
// claim grows with it to the translator's emitted
// text in the host picture. compileBare's driver half
// (the assembling, the linking, the packaging) is not
// ported in this leg, as compileMain's driver half was
// not in the compiler leg; findAssembler, which
// Compiler.swift hosts, is driver machinery of the
// same kind — it reads the process environment and
// tests files for executability, neither of which the
// language can express — and stands with the driver,
// recorded in the README ledger.
//
// This file is a proof harness only — it is not part
// of the toolchain and nothing in src/ depends on it.
//
// Part of Nifla, a public-domain programming language
// by Tyler Kovalevich. See the Unlicense in the LICENSE
// file at the root of this repository.

import Foundation

#if os(Linux)
import Glibc
#endif

@main
struct BareOracle {
    static func main() {
        let args = CommandLine.arguments
        guard args.count >= 3, args[1] == "barevalid" || args[1] == "barevalid-guest" || args[1] == "barecompile" || args[1] == "barecompile-guest" || args[1] == "card" || args[1] == "barecompile-arm" else {
            FileHandle.standardError.write(Data("usage: bare-oracle barevalid|barevalid-guest|barecompile|barecompile-guest|card|barecompile-arm <path>\n".utf8))
            exit(2)
        }
        let guest = args[1] == "barevalid-guest" || args[1] == "barecompile-guest"
        let compile = args[1] == "barecompile" || args[1] == "barecompile-guest"
        let arm = args[1] == "barecompile-arm"
        if args[1] == "card" {
            let path = args[2]
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
                FileHandle.standardError.write(Data("I couldn't read the file at '\(path)'.\n".utf8))
                exit(2)
            }
            let name = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
            FileHandle.standardOutput.write(Data(featherCard(name: name, programBytes: [UInt8](data)).utf8))
            exit(0)
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
            if arm {
                try Checker(program: program, forBareMetal: true, forGuest: false).check(program)
                // Stone 59: drive the real ARM build (see the
                // header). Its fail words are recorded; its
                // assembly is read back from the .s file the
                // build itself writes; its own prints are
                // sent to a scratch file, not the screen.
                let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("bare-oracle-arm-\(ProcessInfo.processInfo.processIdentifier)")
                try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
                let outputPath = scratch.appendingPathComponent("program.elf").path
                var spoken: (text: String, code: Int32)? = nil
                let chatterPath = scratch.appendingPathComponent("chatter.txt").path
                let _ = FileManager.default.createFile(atPath: chatterPath, contents: nil)
                let chatter = FileHandle(forWritingAtPath: chatterPath)!
                let savedStdout = dup(STDOUT_FILENO)
                fflush(stdout)
                dup2(chatter.fileDescriptor, STDOUT_FILENO)
                let _ = compileBareARM(inputPath: path, output: outputPath, program: program, videoRequest: nil, fail: { text, code in
                    spoken = (text, code)
                    return code
                })
                fflush(stdout)
                dup2(savedStdout, STDOUT_FILENO)
                close(savedStdout)
                chatter.closeFile()
                let asmData = try? Data(contentsOf: URL(fileURLWithPath: outputPath + ".s"))
                try? FileManager.default.removeItem(at: scratch)
                if let asmData {
                    FileHandle.standardOutput.write(asmData)
                    exit(0)
                }
                if let spoken {
                    FileHandle.standardError.write(Data((spoken.text + "\n").utf8))
                    exit(spoken.code)
                }
                FileHandle.standardError.write(Data("the ARM build left no assembly behind\n".utf8))
                exit(2)
            }
            try Checker(program: program, forBareMetal: true, forGuest: guest).check(program)
            let validator = BareValidator(guestMode: guest)
            try validator.validate(program)
            if compile {
                var translator = BareTranslator(validator: validator)
                let asm = translator.translate(program, sourceName: URL(fileURLWithPath: path).lastPathComponent)
                FileHandle.standardOutput.write(Data(asm.utf8))
            } else {
                FileHandle.standardOutput.write(Data("valid\n".utf8))
            }
        } catch let error as NiflaError {
            FileHandle.standardError.write(Data((error.spoken + "\n").utf8))
            exit(1)
        } catch {
            FileHandle.standardError.write(Data("\(error)\n".utf8))
            exit(1)
        }
    }
}
