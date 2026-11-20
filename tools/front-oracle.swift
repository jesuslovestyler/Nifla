// Nifla — Stones 47–48 proof harness: the front-end oracle.
//
// A small Swift main that links the untouched toolchain lexer
// and parser (src/Lexer.swift, src/Parser.swift) and dumps a
// source file's tokens, one per line, in exactly the format
// selfhost/nifla-front.nifla's `tokens` mode prints, or —
// Stone 48 — its parse tree as one line, in exactly the
// format the front end's `tree` mode prints:
//
//     number <VALUE> @<line>     VALUE is formatNumber(value)
//     text "<ESC>" @<line>
//     name <word> @<line>
//     keyword <word> @<line>
//     symbol <sym> @<line>
//     floor "<ESC of asm>" @<line>
//     end @<line>
//
// The tree dump's format (single line, single spaces):
//
//     (program + for each statement " " + stmt + ")"
//     (number <formatNumber> @L), (text "<ESC>" @L),
//     (boolean true @L) / (boolean false @L), (nothing @L),
//     (variable <name> @L)
//     (call <name> @L + args + ")"
//     (object @L + for each field " (<name> " + expr + ")" + ")"
//     (list @L + items + ")"
//     (field <base> <name> @L), (index <base> <idx> @L)
//     (floor "<ESC>" @L + args + ")"
//     (negate <expr> @L), (binary <op> @L <left> <right>)
//     (declare <name> <KIND> <expr> @L), (assign <name> <expr> @L),
//     (assign-target <target> <expr> @L), (say <expr> @L),
//     (give <expr> @L)
//     (if <cond> @L (then + stmts + ") (else" + absent: " none",
//       present: stmts + "))"
//     (while <cond> @L + body + ")", (repeat <count> @L + body + ")",
//     (for <name> <over> @L + body + ")"
//     (define <name> @L (params + for each " (<pname> <KIND>)"
//       + ") (returns <KIND>)" + body + ")"
//     (attempt @L (body + stmts + ") (recovery" + stmts + "))"
//     (do-call <name> @L + args + ")", (do-expr <expr> @L)
//
// <KIND> is `none` when there is no annotation, otherwise the
// kind string in double quotes. Both sides build the line by
// accumulating fragments in a list and joining once.
//
// ESC replaces, in this order: backslash -> \\, " -> \",
// newline -> \n, tab -> \t, carriage return -> \r; every other
// character passes through as its own UTF-8 bytes. The escaping
// is an explicit character loop here, and the Nifla side mirrors
// it with a loop of its own — no library escaping on either side.
//
// Exit codes: 0 on success (dump on stdout, nothing on stderr);
// 1 on a lex refusal — or, in tree mode, a parse refusal —
// (nothing on stdout, "Line N: <message>" on stderr); 2 when
// the file itself can't be read as UTF-8 (a plain message on
// stderr; that wording is not part of the identity claim the
// front proofs prove).
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

    // The tree dump's kind annotation: `none` when there is
    // no annotation, otherwise the kind string in quotes.
    static func kindText(_ kind: String?) -> String {
        guard let kind = kind else { return "none" }
        return "\"\(kind)\""
    }

    static func dumpExpr(_ expr: Expr) -> String {
        switch expr {
        case .number(let value, let line):
            return "(number \(formatNumber(value)) @\(line))"
        case .text(let value, let line):
            return "(text \"\(escText(value))\" @\(line))"
        case .boolean(let flag, let line):
            return "(boolean \(flag ? "true" : "false") @\(line))"
        case .nothing(let line):
            return "(nothing @\(line))"
        case .variable(let name, let line):
            return "(variable \(name) @\(line))"
        case .call(let name, let args, let line):
            var parts = ["(call \(name) @\(line)"]
            for arg in args {
                parts.append(" ")
                parts.append(dumpExpr(arg))
            }
            parts.append(")")
            return parts.joined()
        case .object(let fields, let line):
            var parts = ["(object @\(line)"]
            for field in fields {
                parts.append(" (\(field.name) ")
                parts.append(dumpExpr(field.value))
                parts.append(")")
            }
            parts.append(")")
            return parts.joined()
        case .list(let items, let line):
            var parts = ["(list @\(line)"]
            for item in items {
                parts.append(" ")
                parts.append(dumpExpr(item))
            }
            parts.append(")")
            return parts.joined()
        case .field(let base, let name, let line):
            return "(field \(dumpExpr(base)) \(name) @\(line))"
        case .index(let base, let index, let line):
            return "(index \(dumpExpr(base)) \(dumpExpr(index)) @\(line))"
        case .floor(let asm, let args, let line):
            var parts = ["(floor \"\(escText(asm))\" @\(line)"]
            for arg in args {
                parts.append(" ")
                parts.append(dumpExpr(arg))
            }
            parts.append(")")
            return parts.joined()
        case .negate(let inner, let line):
            return "(negate \(dumpExpr(inner)) @\(line))"
        case .binary(let left, let op, let right, let line):
            return "(binary \(op) @\(line) \(dumpExpr(left)) \(dumpExpr(right)))"
        }
    }

    // " stmt stmt ..." — a block's fragments, joined once.
    static func dumpBlock(_ stmts: [Stmt]) -> String {
        var parts: [String] = []
        for stmt in stmts {
            parts.append(" ")
            parts.append(dumpStmt(stmt))
        }
        return parts.joined()
    }

    static func dumpStmt(_ stmt: Stmt) -> String {
        switch stmt {
        case .declare(let name, let kind, let value, let line):
            return "(declare \(name) \(kindText(kind)) \(dumpExpr(value)) @\(line))"
        case .assign(let name, let value, let line):
            return "(assign \(name) \(dumpExpr(value)) @\(line))"
        case .assignTarget(let target, let value, let line):
            return "(assign-target \(dumpExpr(target)) \(dumpExpr(value)) @\(line))"
        case .say(let value, let line):
            return "(say \(dumpExpr(value)) @\(line))"
        case .ifElse(let condition, let then, let otherwise, let line):
            var parts = ["(if \(dumpExpr(condition)) @\(line) (then"]
            parts.append(dumpBlock(then))
            parts.append(") (else")
            if let otherwise = otherwise {
                parts.append(dumpBlock(otherwise))
            } else {
                parts.append(" none")
            }
            parts.append("))")
            return parts.joined()
        case .whileLoop(let condition, let body, let line):
            return "(while \(dumpExpr(condition)) @\(line)\(dumpBlock(body)))"
        case .repeatLoop(let count, let body, let line):
            return "(repeat \(dumpExpr(count)) @\(line)\(dumpBlock(body)))"
        case .forEach(let name, let over, let body, let line):
            return "(for \(name) \(dumpExpr(over)) @\(line)\(dumpBlock(body)))"
        case .define(let name, let params, let paramKinds, let returnKind, let body, let line):
            var parts = ["(define \(name) @\(line) (params"]
            for i in params.indices {
                parts.append(" (\(params[i]) \(kindText(paramKinds[i])))")
            }
            parts.append(") (returns \(kindText(returnKind)))")
            parts.append(dumpBlock(body))
            parts.append(")")
            return parts.joined()
        case .give(let value, let line):
            return "(give \(dumpExpr(value)) @\(line))"
        case .attempt(let body, let recovery, let line):
            return "(attempt @\(line) (body\(dumpBlock(body))) (recovery\(dumpBlock(recovery))))"
        case .doCall(let name, let args, let line):
            var parts = ["(do-call \(name) @\(line)"]
            for arg in args {
                parts.append(" ")
                parts.append(dumpExpr(arg))
            }
            parts.append(")")
            return parts.joined()
        case .doExpr(let expr, let line):
            return "(do-expr \(dumpExpr(expr)) @\(line))"
        }
    }

    static func dumpProgram(_ stmts: [Stmt]) -> String {
        var parts = ["(program"]
        parts.append(dumpBlock(stmts))
        parts.append(")")
        return parts.joined()
    }

    static func main() {
        let args = CommandLine.arguments
        guard args.count >= 3, args[1] == "tokens" || args[1] == "tree" else {
            FileHandle.standardError.write(Data("usage: front-oracle tokens|tree <path>\n".utf8))
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
            if mode == "tokens" {
                var lines: [String] = []
                for token in tokens {
                    lines.append(dumpToken(token))
                }
                print(lines.joined(separator: "\n"))
            } else {
                let stmts = try Parser(tokens).parseProgram()
                print(dumpProgram(stmts))
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
