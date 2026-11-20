// Nifla — Stone 47 proof harness: the front-end oracle.
//
// A small Swift main that links the untouched toolchain lexer
// (src/Lexer.swift; src/Parser.swift rides along, harmless now,
// needed when the parser joins the front end in Stone 48) and
// dumps a source file's tokens, one per line, in exactly the
// format selfhost/nifla-front.nifla's `tokens` mode prints:
//
//     number <VALUE> @<line>     VALUE is formatNumber(value)
//     text "<ESC>" @<line>
//     name <word> @<line>
//     keyword <word> @<line>
//     symbol <sym> @<line>
//     floor "<ESC of asm>" @<line>
//     end @<line>
//
// ESC replaces, in this order: backslash -> \\, " -> \",
// newline -> \n, tab -> \t, carriage return -> \r; every other
// character passes through as its own UTF-8 bytes. The escaping
// is an explicit character loop here, and the Nifla side mirrors
// it with a loop of its own — no library escaping on either side.
//
// Exit codes: 0 on success (dump on stdout, nothing on stderr);
// 1 on a lex refusal (nothing on stdout, "Line N: <message>" on
// stderr); 2 when the file itself can't be read as UTF-8 (a
// plain message on stderr; that wording is not part of the
// identity claim run-front-lexer.sh proves).
//
// This file is a proof harness only — it is not part of the
// toolchain and nothing in src/ depends on it.
//
// Part of Nifla, a public-domain programming language by Tyler
// Kovalevich. See the Unlicense in the LICENSE file at the root
// of this repository.

import Foundation

@main
struct FrontOracle {
    static func escText(_ value: String) -> String {
        var out = ""
        for ch in value {
            if ch == "\\" {
                out += "\\\\"
            } else if ch == "\"" {
                out += "\\\""
            } else if ch == "\n" {
                out += "\\n"
            } else if ch == "\t" {
                out += "\\t"
            } else if ch == "\r" {
                out += "\\r"
            } else {
                out.append(ch)
            }
        }
        return out
    }

    static func dumpToken(_ token: Token) -> String {
        switch token.kind {
        case .number(let value):
            return "number \(formatNumber(value)) @\(token.line)"
        case .text(let value):
            return "text \"\(escText(value))\" @\(token.line)"
        case .name(let value):
            return "name \(value) @\(token.line)"
        case .keyword(let value):
            return "keyword \(value) @\(token.line)"
        case .symbol(let value):
            return "symbol \(value) @\(token.line)"
        case .floor(let asm):
            return "floor \"\(escText(asm))\" @\(token.line)"
        case .end:
            return "end @\(token.line)"
        }
    }

    static func main() {
        let args = CommandLine.arguments
        guard args.count >= 3, args[1] == "tokens" else {
            FileHandle.standardError.write(Data("usage: front-oracle tokens <path>\n".utf8))
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
            var lines: [String] = []
            for token in tokens {
                lines.append(dumpToken(token))
            }
            print(lines.joined(separator: "\n"))
        } catch let error as NiflaError {
            FileHandle.standardError.write(Data((error.spoken + "\n").utf8))
            exit(1)
        } catch {
            FileHandle.standardError.write(Data("\(error)\n".utf8))
            exit(1)
        }
    }
}
