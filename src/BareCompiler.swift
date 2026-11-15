// BareCompiler.swift — Stone 11: the bare-metal target.
//
// `niflac --bare program.nifla` compiles a restricted subset
// of Nifla into a freestanding binary: no operating system, no
// Swift runtime, nothing underneath but the processor. The
// Swift-codegen path can't do this — its output carries the
// Swift runtime with it — so this file holds its own two
// pieces:
//
//   BareValidator — walks the checked program and refuses, in
//     plain words and before anything is built, whatever the
//     bare subset doesn't include. The subset: whole numbers,
//     text (literals and variables, length, and ==/!=), true
//     and false, variables, if/else, while, repeat, functions
//     that make and give, and floor blocks with the Stone 9
//     desk (text crosses it on the bytes side, rbx/r12; there
//     is no results desk — r13 is 0 — so a bare floor block
//     gives back only its rax number). Everything else — say,
//     objects, lists, bytes values, files, attempt, for, and
//     every built-in tool except length — is refused.
//
//   BareTranslator — turns the validated program into x86-64
//     assembly directly: a multiboot header and a 32-bit stub
//     that builds page tables, switches the processor into
//     64-bit long mode, and calls the program; the program's
//     own functions and statements as machine code; its floor
//     blocks as raw functions behind the desk. compileMain
//     assembles and links it (see compileBare there).
//
// Stone 12 adds the machine's first doors: the emitted stub
// now also builds an interrupt table, remaps the interrupt
// controllers, sets the timer ticking a hundred times a
// second, and switches interrupts on before the program
// starts. Three bare-only tools read the machine: ticks(),
// readkey(), and waittick() (see bareOnlyTools below).
//
// How values live on the machine: a number or a true/false is
// one 64-bit word (booleans are 1 and 0). Text is two words —
// a pointer to its characters and their count — because bare
// metal has no one to own a string. Function values travel in
// the machine's own registers, up to six words' worth. The
// two runaway guards keep their numbers (a million loop
// passes, five hundred nested calls) but on bare metal they
// stop the machine itself: there is no one to speak to.

import Foundation

// The bare-only tools: names that exist on bare metal and
// nowhere else, with the number of values each takes. The
// checker knows them when (and only when) it checks for the
// bare target; the bare validator admits them; the bare
// translator emits them as reads of the machine itself.
// Stone 12 gave the first three: the timer's tick count, the
// keyboard's next scancode, and a wait for the next tick.
// Later bare stones add their own here.
let bareOnlyTools: [String: Int] = [
    "ticks": 0,
    "readkey": 0,
    "waittick": 0,
    "memorysize": 0,
]

// The shape of a value, as far as bare metal needs to know it.
// .unknown is a value whose shape the validator hasn't pinned
// down — a function parameter before any use or call says what
// it is. Unpinned values are machine words (numbers) unless a
// use or a call pins them to text.
enum BareKind {
    case number
    case text
    case boolean
    case bytes
    case unknown
}

final class BareValidator {
    // Function shapes, by name: parameter names, and the kind
    // the function gives back (filled in as bodies are read).
    private(set) var functions: [String: (params: [String], giveKind: BareKind)] = [:]
    private var defineLines: [String: Int] = [:]
    private var definitionOrder: [String] = []
    // The pinned kind of each function's parameters, by index —
    // learned from uses inside the body and from calls alike.
    private(set) var paramKinds: [String: [BareKind]] = [:]

    private var scopes: [[String: BareKind]] = []
    private var currentFunction: String? = nil

    func validate(_ program: [Stmt]) throws {
        // Functions are collected from the program's top level
        // only; a 'make' anywhere else is refused when met.
        for statement in program {
            if case .define(let name, let params, _, let line) = statement {
                if bareOnlyTools[name] != nil {
                    throw NiflaError(line: line, message: "There is already a bare-metal tool called '\(name)' — every bare program has it from the start. A function can't be made with that name; rename the function.")
                }
                functions[name] = (params: params, giveKind: .unknown)
                defineLines[name] = line
                definitionOrder.append(name)
                paramKinds[name] = [BareKind](repeating: .unknown, count: params.count)
            }
        }
        // Bodies first, in the order they were written, then
        // the program's own statements.
        for statement in program {
            if case .define(let name, _, let body, _) = statement {
                try validateFunction(name: name, body: body)
            }
        }
        scopes = [[:]]
        currentFunction = nil
        for statement in program {
            if case .define = statement { continue }
            try validateStatement(statement, topLevel: true)
        }
        scopes = []
    }

    private func validateFunction(name: String, body: [Stmt]) throws {
        let info = functions[name]!
        scopes = [[String: BareKind](uniqueKeysWithValues: zip(info.params, paramKinds[name]!))]
        currentFunction = name
        for statement in body {
            try validateStatement(statement, topLevel: false)
        }
        // Write back whatever the body's uses pinned down.
        for (index, param) in info.params.enumerated() {
            let pinned = scopes[0][param] ?? .unknown
            if pinned != .unknown {
                if paramKinds[name]![index] != .unknown && paramKinds[name]![index] != pinned {
                    throw NiflaError(line: defineLines[name]!, message: "The function '\(name)' uses its value '\(param)' as \(kindPhrase(pinned)), but a call hands it \(kindPhrase(paramKinds[name]![index])). On bare metal a value's shape has to be one thing — change the call, or how the function uses '\(param)'.")
                }
                paramKinds[name]![index] = pinned
            }
        }
        scopes = []
        currentFunction = nil
    }

    private func kindPhrase(_ kind: BareKind) -> String {
        switch kind {
        case .number: return "a number"
        case .text: return "text"
        case .boolean: return "true or false"
        case .bytes: return "a block of bytes"
        case .unknown: return "a machine word"
        }
    }

    // MARK: scopes and pinning

    private func lookup(_ name: String) -> BareKind? {
        for scope in scopes.reversed() {
            if let kind = scope[name] { return kind }
        }
        return nil
    }

    // Pins a variable to a kind: the first pin wins, and a
    // conflicting pin is refused at this line.
    private func pin(_ name: String, to kind: BareKind, line: Int) throws {
        for index in scopes.indices.reversed() {
            if let existing = scopes[index][name] {
                if existing == .unknown {
                    scopes[index][name] = kind
                } else if existing != kind {
                    throw NiflaError(line: line, message: "This uses '\(name)' as \(kindPhrase(kind)), but '\(name)' already holds \(kindPhrase(existing)). On bare metal a value's shape has to be one thing.")
                }
                return
            }
        }
    }

    // The kind an expression provably has, checking everything
    // inside it on the way.
    private func kindOf(_ expr: Expr) throws -> BareKind {
        switch expr {
        case .number(let value, let line):
            guard value == value.rounded() && abs(value) < 1e15 else {
                throw NiflaError(line: line, message: "On bare metal every number is a whole number that fits the machine, but this one is \(formatNumber(value)). Use a whole number — division there gives the whole quotient, too.")
            }
            return .number

        case .text:
            return .text

        case .boolean:
            return .boolean

        case .variable(let name, _):
            return lookup(name) ?? .unknown

        case .call(let name, let args, let line):
            return try callKind(name: name, args: args, line: line)

        case .object(_, let line):
            throw NiflaError(line: line, message: "Objects aren't part of bare metal yet — there is no one there to own their fields. Bare metal has numbers, text, and true or false.")

        case .list(_, let line):
            throw NiflaError(line: line, message: "Lists aren't part of bare metal yet — there is no one there to own their items. Bare metal has numbers, text, and true or false.")

        case .field(_, _, let line):
            throw NiflaError(line: line, message: "Reading a field isn't part of bare metal yet — there are no objects there.")

        case .index(let base, let index, let line):
            // Stone 13: a block of bytes is the one numbered
            // memory on bare metal — bytes[b] reads a byte.
            // (Lists and text still can't be indexed there.)
            var baseKind = try kindOf(base)
            if baseKind == .unknown, case .variable(let name, _) = base {
                try pin(name, to: .bytes, line: line)
                baseKind = .bytes
            }
            guard baseKind == .bytes else {
                throw NiflaError(line: line, message: "Taking an item by number on bare metal works on a block of bytes — made with makebytes — but here the value being picked from is \(kindPhrase(baseKind)). Lists and text can't be picked apart there.")
            }
            try requireNumber(index, line: line, doing: "pick a byte")
            return .number

        case .floor(_, let args, let line):
            var memoryCount = 0
            for arg in args {
                let kind = try kindOf(arg)
                switch kind {
                case .number:
                    break
                case .text, .bytes:
                    // Text and blocks of bytes both cross on
                    // the desk's one memory side (Stone 13).
                    memoryCount += 1
                case .boolean:
                    throw NiflaError(line: line, message: "A floor block can be handed numbers and one piece of text or block of bytes, but it was handed true or false. Hand it a number instead — 1 for true, 0 for false.")
                case .unknown:
                    throw NiflaError(line: line, message: "I can't tell whether this value handed to a floor block is a number or memory, and on bare metal the desk differs — numbers in a row, memory on the memory side. Give the block a value whose shape is plain where it's handed: a number, a piece of text, a block of bytes, or a variable holding one of those.")
                }
            }
            if memoryCount > 1 {
                throw NiflaError(line: line, message: "A floor block can be handed only one piece of text or block of bytes — the desk has one memory side (rbx and r12). Hand the rest as numbers, or work on the other memory from inside the block.")
            }
            return .number

        case .negate(let inner, let line):
            try requireNumber(inner, line: line, doing: "be turned into its negative")
            return .number

        case .binary(let left, let op, let right, let line):
            switch op {
            case "+":
                let leftKind = try kindOf(left)
                let rightKind = try kindOf(right)
                if leftKind == .text || rightKind == .text {
                    throw NiflaError(line: line, message: "Text can't be joined together on bare metal yet — there is no one there to own the joined text. Text there can be held, measured with length, compared, and handed to a floor block.")
                }
                if leftKind == .boolean || rightKind == .boolean {
                    throw NiflaError(line: line, message: "True and false can't be added on bare metal — arithmetic there is for numbers, as it is everywhere in Nifla.")
                }
                if leftKind == .bytes || rightKind == .bytes {
                    throw NiflaError(line: line, message: "A block of bytes can't be added on bare metal — arithmetic there is for numbers. Work with one byte at a time, like block[0], or hand the block to a floor block.")
                }
                return .number
            case "-", "*", "/":
                try requireNumber(left, line: line, doing: "be part of arithmetic")
                try requireNumber(right, line: line, doing: "be part of arithmetic")
                return .number
            case "<", "<=", ">", ">=":
                try requireNumber(left, line: line, doing: "be compared by size")
                try requireNumber(right, line: line, doing: "be compared by size")
                return .boolean
            case "==", "!=":
                let leftKind = try kindOf(left)
                let rightKind = try kindOf(right)
                if leftKind == .bytes || rightKind == .bytes {
                    throw NiflaError(line: line, message: "Blocks of bytes can't be compared on bare metal — compare their lengths, or a byte at a time, like block[0] == 65.")
                }
                if leftKind != .unknown && rightKind != .unknown && leftKind != rightKind {
                    throw NiflaError(line: line, message: "On bare metal, comparing needs both sides to be the same kind of value — numbers with numbers, text with text — but here one side is \(kindPhrase(leftKind)) and the other is \(kindPhrase(rightKind)).")
                }
                // An unpinned variable compared with text is
                // pinned to text; compared with anything else,
                // to a machine word.
                if leftKind == .text || rightKind == .text {
                    if case .variable(let name, _) = left { try pin(name, to: .text, line: line) }
                    if case .variable(let name, _) = right { try pin(name, to: .text, line: line) }
                }
                return .boolean
            default:
                throw NiflaError(line: line, message: "The sign '\(op)' isn't part of bare metal yet.")
            }
        }
    }

    // Requires an expression to be usable as a number: a proven
    // other kind is refused, an unpinned variable is pinned.
    private func requireNumber(_ expr: Expr, line: Int, doing: String) throws {
        let kind = try kindOf(expr)
        switch kind {
        case .number, .unknown:
            if case .variable(let name, _) = expr, kind == .unknown {
                try pin(name, to: .number, line: line)
            }
        case .text:
            throw NiflaError(line: line, message: "Text can't \(doing) — arithmetic on bare metal is for numbers, as it is everywhere in Nifla.")
        case .boolean:
            throw NiflaError(line: line, message: "True and false can't \(doing) — arithmetic on bare metal is for numbers, as it is everywhere in Nifla.")
        case .bytes:
            throw NiflaError(line: line, message: "A block of bytes can't \(doing) — arithmetic on bare metal is for numbers. Work with one byte at a time, like block[0], or hand the block to a floor block.")
        }
    }

    // Checks a call — a bare-only tool, a built-in tool, or a
    // made function — and gives back the kind it hands back.
    private func callKind(name: String, args: [Expr], line: Int) throws -> BareKind {
        if let arity = bareOnlyTools[name] {
            // The bare-only tools (Stone 12) read the machine
            // itself and take no values; each hands back a
            // number. (The checker has verified the count
            // already; this is the same refusal in the
            // validator's own voice, for safety.)
            for arg in args { _ = try kindOf(arg) }
            guard args.count == arity else {
                throw NiflaError(line: line, message: "'\(name)' takes no values, but it was given \(args.count). It reads the machine itself — call it with nothing between the parentheses: \(name)().")
            }
            return .number
        }
        if builtinTools[name] != nil {
            if name == "makebytes" {
                // Stone 13: blocks of bytes came to bare metal,
                // backed by the allocator over the machine's
                // real free memory.
                guard args.count == 1 else {
                    throw NiflaError(line: line, message: "'makebytes' takes 1 value (count), but it was given \(args.count).")
                }
                try requireNumber(args[0], line: line, doing: "say how many bytes to make")
                return .bytes
            }
            guard name == "length" else {
                throw NiflaError(line: line, message: "The tool '\(name)' isn't part of bare metal yet — there is no screen, no files, and no one to give tools there. Bare metal keeps 'length', for measuring text and blocks of bytes.")
            }
            guard args.count == 1 else {
                throw NiflaError(line: line, message: "'length' takes 1 value (value), but it was given \(args.count).")
            }
            let kind = try kindOf(args[0])
            if kind == .number || kind == .boolean {
                throw NiflaError(line: line, message: "On bare metal 'length' measures text and blocks of bytes only — lists and objects, which it also measures in hosted Nifla, aren't there.")
            }
            if kind == .unknown, case .variable(let varName, _) = args[0] {
                try pin(varName, to: .text, line: line)
            }
            return .number
        }
        guard let info = functions[name] else {
            // The checker has already refused unknown names;
            // reaching here would mean the two disagree.
            throw NiflaError(line: line, message: "I don't know a function called '\(name)'.")
        }
        var slots = 0
        for (index, arg) in args.enumerated() {
            let kind = try kindOf(arg)
            slots += (kind == .text || kind == .bytes ? 2 : 1)
            if index < info.params.count, kind != .unknown {
                if paramKinds[name]![index] == .unknown {
                    paramKinds[name]![index] = kind
                } else if paramKinds[name]![index] != kind {
                    throw NiflaError(line: line, message: "This call hands '\(name)' \(kindPhrase(kind)) for its value '\(info.params[index])', but another call hands it \(kindPhrase(paramKinds[name]![index])). On bare metal a value's shape has to be one thing.")
                }
            }
        }
        if slots > 6 {
            throw NiflaError(line: line, message: "This call hands '\(name)' more values than the machine's registers can carry — six words' worth is the most (a piece of text takes two). Hand fewer values, or pack numbers into fewer words.")
        }
        return info.giveKind
    }

    // MARK: statements

    private func validateBlock(_ statements: [Stmt]) throws {
        scopes.append([:])
        for statement in statements {
            try validateStatement(statement, topLevel: false)
        }
        scopes.removeLast()
    }

    private func validateStatement(_ statement: Stmt, topLevel: Bool) throws {
        switch statement {
        case .declare(let name, let value, _):
            var kind = try kindOf(value)
            if kind == .unknown {
                // A copy of an unpinned variable, or the result
                // of a call whose give isn't known yet: it lives
                // as a machine word.
                if case .variable(let source, let line) = value {
                    try pin(source, to: .number, line: line)
                }
                kind = .number
            }
            scopes[scopes.count - 1][name] = kind

        case .assign(let name, let value, let line):
            var kind = try kindOf(value)
            if kind == .unknown {
                if case .variable(let source, let srcLine) = value {
                    try pin(source, to: .number, line: srcLine)
                }
                kind = .number
            }
            if let existing = lookup(name), existing != .unknown, kind != existing {
                throw NiflaError(line: line, message: "This sets '\(name)' to \(kindPhrase(kind)), but '\(name)' already holds \(kindPhrase(existing)). On bare metal a value's shape has to be one thing.")
            }
            if lookup(name) == .unknown || lookup(name) == nil {
                try pin(name, to: kind, line: line)
            }

        case .assignTarget(let target, let value, let line):
            // Stone 13: setting a byte in a block of bytes is
            // the one setting-by-place bare metal has. Fields
            // (objects) and list items remain outside it.
            if case .index(let base, let index, _) = target {
                var baseKind = try kindOf(base)
                if baseKind == .unknown, case .variable(let name, _) = base {
                    try pin(name, to: .bytes, line: line)
                    baseKind = .bytes
                }
                guard baseKind == .bytes else {
                    throw NiflaError(line: line, message: "Setting an item by number on bare metal works on a block of bytes — made with makebytes — but here the value being set into is \(kindPhrase(baseKind)).")
                }
                try requireNumber(index, line: line, doing: "pick a byte")
                try requireNumber(value, line: line, doing: "be stored as a byte")
                return
            }
            throw NiflaError(line: line, message: "Setting a field isn't part of bare metal yet — there are no objects there. Setting a byte in a block of bytes, like block[0] = 65, is the one setting-by-place it has.")

        case .say(_, let line):
            throw NiflaError(line: line, message: "Bare metal has no screen for 'say' yet — there is no one to say it to. To put words on the screen there, hand the text to a floor block and let it write to the screen's memory (0xB8000) itself.")

        case .ifElse(let condition, let then, let otherwise, let line):
            let kind = try kindOf(condition)
            if kind == .number || kind == .text {
                throw NiflaError(line: line, message: "This 'if' decides with \(kindPhrase(kind)), but a decision needs true or false — compare something, like: if style == 15 { ... }.")
            }
            try validateBlock(then)
            if let otherwise { try validateBlock(otherwise) }

        case .whileLoop(let condition, let body, let line):
            let kind = try kindOf(condition)
            if kind == .number || kind == .text {
                throw NiflaError(line: line, message: "This 'while' decides with \(kindPhrase(kind)), but a decision needs true or false — compare something, like: while count < 5 { ... }.")
            }
            try validateBlock(body)

        case .repeatLoop(let count, let body, let line):
            let kind = try kindOf(count)
            if kind == .text || kind == .boolean {
                throw NiflaError(line: line, message: "'repeat' needs a number saying how many times to run, but here it was given \(kindPhrase(kind)).")
            }
            try validateBlock(body)

        case .forEach(_, _, _, let line):
            throw NiflaError(line: line, message: "'for' isn't part of bare metal yet — there are no lists there. Walk a block of bytes with 'while' and a counter instead.")

        case .define(let name, _, _, let line):
            if topLevel {
                // Already collected and validated; nested or
                // stray defines never reach here as topLevel.
                _ = name
            } else {
                throw NiflaError(line: line, message: "On bare metal, functions are made at the top of the program — a 'make' inside a block or another function isn't part of it yet.")
            }

        case .give(let value, _):
            let kind = try kindOf(value)
            if let function = currentFunction, kind != .unknown {
                let existing = functions[function]!.giveKind
                if existing != .unknown && existing != kind {
                    throw NiflaError(line: defineLines[function]!, message: "The function '\(function)' gives back \(kindPhrase(existing)) in one place and \(kindPhrase(kind)) in another. On bare metal what a function gives has to be one shape.")
                }
                functions[function]!.giveKind = kind
            }

        case .attempt(_, _, let line):
            throw NiflaError(line: line, message: "'attempt' isn't part of bare metal yet — on bare metal a problem stops the machine itself, and there is nothing there to catch it with.")

        case .doCall(let name, let args, let line):
            _ = try callKind(name: name, args: args, line: line)

        case .doExpr(let expr, _):
            _ = try kindOf(expr)
        }
    }
}

// MARK: - The bare translator

struct BareTranslator {
    private let functions: [String: (params: [String], giveKind: BareKind)]
    private let paramKinds: [String: [BareKind]]

    private var code: [String] = []
    private var literals: [(label: String, bytes: [UInt8])] = []
    private var floorBlocks: [String] = []
    private var labelCounter = 0

    // One function (or the program itself) being emitted: its
    // variables' frame offsets and kinds, scope by scope, and
    // how much frame has been handed out.
    private var scopes: [[String: (offset: Int, kind: BareKind)]] = []
    private var nextOffset = 0
    private var currentExitLabel = "__nifla_main_exit"
    private var currentFunction: String? = nil

    init(validator: BareValidator) {
        functions = validator.functions
        paramKinds = validator.paramKinds
    }

    private mutating func freshLabel(_ base: String) -> String {
        labelCounter += 1
        return "__\(base)_\(labelCounter)"
    }

    private mutating func emit(_ line: String) {
        code.append(line)
    }

    // The kind an expression has, derived the same way the
    // validator derives it — but now every parameter kind and
    // give kind is final, so the answer is the machine's truth.
    private func kindOf(_ expr: Expr) -> BareKind {
        switch expr {
        case .number: return .number
        case .text: return .text
        case .boolean: return .boolean
        case .variable(let name, _):
            for scope in scopes.reversed() {
                if let entry = scope[name] { return entry.kind }
            }
            return .number
        case .call(let name, _, _):
            if name == "length" { return .number }
            if name == "makebytes" { return .bytes }
            if bareOnlyTools[name] != nil { return .number }
            return functions[name]?.giveKind ?? .number
        case .floor: return .number
        case .negate: return .number
        case .binary(_, let op, _, _):
            switch op {
            case "<", "<=", ">", ">=", "==", "!=": return .boolean
            default: return .number
            }
        case .object, .list, .field, .index:
            return .number  // refused by the validator; never emitted
        }
    }

    private func slots(for kind: BareKind) -> Int {
        (kind == .text || kind == .bytes) ? 2 : 1
    }

    private mutating func declareVar(_ name: String, kind: BareKind) -> (offset: Int, kind: BareKind) {
        nextOffset += 8 * slots(for: kind)
        let entry = (offset: nextOffset, kind: kind)
        scopes[scopes.count - 1][name] = entry
        return entry
    }

    private func lookupVar(_ name: String) -> (offset: Int, kind: BareKind) {
        for scope in scopes.reversed() {
            if let entry = scope[name] { return entry }
        }
        return (offset: 0, kind: .number)  // the checker proved it exists
    }

    // MARK: the whole file

    mutating func translate(_ program: [Stmt], sourceName: String) -> String {
        // Functions first (their text literals and floor blocks
        // are collected on the way), then the program itself.
        var functionCode: [String] = []
        for statement in program {
            if case .define(let name, _, let body, _) = statement {
                code = []
                emitFunction(name: name, body: body)
                functionCode += code
            }
        }
        code = []
        emitMain(program)
        let mainCode = code

        var out: [String] = []
        out.append("// Bare metal, from \(sourceName), by niflac --bare (Nifla Stone 11).")
        out.append("// No operating system, no runtime: a multiboot header, a")
        out.append("// 32-bit stub that builds page tables and switches the")
        out.append("// processor into 64-bit long mode, then the program itself.")
        out.append("    .intel_syntax noprefix")
        out.append("")
        out.append("    .section .multiboot")
        out.append("    .align 4")
        out.append("    .long 0x1BADB002")
        out.append("    .long 0x2")
        out.append("    .long -(0x1BADB002 + 0x2)")
        out.append("")
        out.append("    .section .text")
        out.append("    .code32")
        out.append("    .globl _start32")
        out.append("_start32:")
        out.append("    mov [__mb_info], ebx")
        out.append("    mov [__mb_magic], eax")
        out.append("    mov esp, offset __stack_top")
        out.append("    mov eax, offset __pdpt")
        out.append("    or eax, 0x3")
        out.append("    mov [__pml4], eax")
        out.append("    mov eax, offset __pd")
        out.append("    or eax, 0x3")
        out.append("    mov [__pdpt], eax")
        out.append("    xor ecx, ecx")
        out.append("__pd_fill:")
        out.append("    mov eax, ecx")
        out.append("    shl eax, 21")
        out.append("    or eax, 0x83")
        out.append("    mov [__pd + ecx * 8], eax")
        out.append("    mov dword ptr [__pd + ecx * 8 + 4], 0")
        out.append("    inc ecx")
        out.append("    cmp ecx, 512")
        out.append("    jne __pd_fill")
        out.append("    mov eax, offset __pml4")
        out.append("    mov cr3, eax")
        out.append("    mov eax, cr4")
        out.append("    or eax, 0x20")
        out.append("    mov cr4, eax")
        out.append("    mov ecx, 0xC0000080")
        out.append("    rdmsr")
        out.append("    or eax, 0x100")
        out.append("    wrmsr")
        out.append("    mov eax, cr0")
        out.append("    or eax, 0x80000000")
        out.append("    mov cr0, eax")
        out.append("    lgdt [__gdt_ptr]")
        out.append("    push 0x08")
        out.append("    push offset __long_entry")
        out.append("    retf")
        out.append("")
        out.append("    .code64")
        out.append("__long_entry:")
        out.append("    mov ax, 0x10")
        out.append("    mov ds, ax")
        out.append("    mov es, ax")
        out.append("    mov fs, ax")
        out.append("    mov gs, ax")
        out.append("    mov ss, ax")
        out.append("    call __nifla_memory_init")
        out.append("    call __nifla_interrupts_init")
        out.append("    call __nifla_main")
        out.append("__halt_trap:")
        out.append("    cli")
        out.append("    hlt")
        out.append("    jmp __halt_trap")
        out.append("")
        out.append("// Text comparison: rax/r8 hold the two texts (pointer in")
        out.append("// rax and rcx, count in rdx and r8). Answers 1 or 0 in rax.")
        out.append("__nifla_text_eq:")
        out.append("    cmp rdx, r8")
        out.append("    jne __text_eq_no")
        out.append("    xor r9d, r9d")
        out.append("__text_eq_loop:")
        out.append("    cmp r9, rdx")
        out.append("    jae __text_eq_yes")
        out.append("    movzx r10d, byte ptr [rax + r9]")
        out.append("    cmp r10b, byte ptr [rcx + r9]")
        out.append("    jne __text_eq_no")
        out.append("    inc r9")
        out.append("    jmp __text_eq_loop")
        out.append("__text_eq_yes:")
        out.append("    mov rax, 1")
        out.append("    ret")
        out.append("__text_eq_no:")
        out.append("    xor eax, eax")
        out.append("    ret")
        out.append("")
        out.append("// Stone 13: the machine learns what memory it has.")
        out.append("// The loader handed over a map of the machine's")
        out.append("// memory (the multiboot map, asked for in the")
        out.append("// header); this walk adds up the usable stretches")
        out.append("// into __mem_total, and finds the usable stretch")
        out.append("// the program itself sits in — everything from the")
        out.append("// program's end to that stretch's end is the heap.")
        out.append("// The allocator is a bump allocator: each makebytes")
        out.append("// takes the next slice, rounded up to a whole 16")
        out.append("// bytes, and zeroes it. Nothing is ever handed")
        out.append("// back — there is no free — and a request past the")
        out.append("// heap's end, or past one block's 16 MiB cap, stops")
        out.append("// the machine rather than corrupt anything.")
        out.append("__nifla_memory_init:")
        out.append("    mov eax, [__mb_magic]")
        out.append("    cmp eax, 0x2BADB002")
        out.append("    jne __mem_done")
        out.append("    mov esi, [__mb_info]")
        out.append("    test rsi, rsi")
        out.append("    jz __mem_done")
        out.append("    mov eax, [rsi]")
        out.append("    test eax, 0x40")
        out.append("    jz __mem_done")
        out.append("    mov ecx, [rsi + 44]")
        out.append("    mov esi, [rsi + 48]")
        out.append("    mov rdx, rsi")
        out.append("    add rdx, rcx")
        out.append("__mem_walk:")
        out.append("    cmp rsi, rdx")
        out.append("    jae __mem_done")
        out.append("    cmp dword ptr [rsi + 20], 1")
        out.append("    jne __mem_next")
        out.append("    mov rax, [rsi + 12]")
        out.append("    add [__mem_total], rax")
        out.append("    mov rax, [rsi + 4]")
        out.append("    mov r8, offset __kernel_end")
        out.append("    cmp r8, rax")
        out.append("    jb __mem_next")
        out.append("    add rax, [rsi + 12]")
        out.append("    cmp r8, rax")
        out.append("    jae __mem_next")
        out.append("    mov [__heap_limit], rax")
        out.append("__mem_next:")
        out.append("    mov eax, [rsi]")
        out.append("    add rax, 4")
        out.append("    add rsi, rax")
        out.append("    jmp __mem_walk")
        out.append("__mem_done:")
        out.append("    mov rax, offset __kernel_end")
        out.append("    add rax, 15")
        out.append("    and rax, -16")
        out.append("    mov [__heap_cursor], rax")
        out.append("    ret")
        out.append("")
        out.append("// makebytes' engine: a count in rax becomes a block")
        out.append("// — its address in rax, its count in rdx.")
        out.append("__nifla_alloc:")
        out.append("    cmp rax, 16777216")
        out.append("    ja __halt_trap")
        out.append("    mov rdx, rax")
        out.append("    add rax, 15")
        out.append("    and rax, -16")
        out.append("    mov r8, rax")
        out.append("    mov rax, [__heap_cursor]")
        out.append("    mov rcx, rax")
        out.append("    add rcx, r8")
        out.append("    cmp rcx, [__heap_limit]")
        out.append("    ja __halt_trap")
        out.append("    mov [__heap_cursor], rcx")
        out.append("    mov r9, rax")
        out.append("    mov rdi, rax")
        out.append("    mov rcx, r8")
        out.append("    xor eax, eax")
        out.append("    rep stosb")
        out.append("    mov rax, r9")
        out.append("    ret")
        out.append("")
        out.append("// Stone 12: the machine learns to listen. An interrupt")
        out.append("// table is built and loaded; the two interrupt")
        out.append("// controllers (the PIC pair) are remapped so the timer")
        out.append("// arrives as interrupt 32 and the keyboard as 33; the")
        out.append("// timer chip (the PIT) is set ticking a hundred times")
        out.append("// a second; then interrupts are switched on. Every")
        out.append("// door but the timer's and the keyboard's leads to a")
        out.append("// stub that simply returns — a door nobody uses yet.")
        out.append("__nifla_interrupts_init:")
        out.append("    lea rdi, [__idt]")
        out.append("    mov rax, offset __irq_default")
        out.append("    mov rcx, 256")
        out.append("__idt_fill:")
        out.append("    call __idt_set")
        out.append("    add rdi, 16")
        out.append("    dec rcx")
        out.append("    jne __idt_fill")
        out.append("    lea rdi, [__idt + 512]")
        out.append("    mov rax, offset __irq_timer")
        out.append("    call __idt_set")
        out.append("    lea rdi, [__idt + 528]")
        out.append("    mov rax, offset __irq_keyboard")
        out.append("    call __idt_set")
        out.append("    mov al, 0x11")
        out.append("    out 0x20, al")
        out.append("    call __io_wait")
        out.append("    out 0xA0, al")
        out.append("    call __io_wait")
        out.append("    mov al, 0x20")
        out.append("    out 0x21, al")
        out.append("    call __io_wait")
        out.append("    mov al, 0x28")
        out.append("    out 0xA1, al")
        out.append("    call __io_wait")
        out.append("    mov al, 0x04")
        out.append("    out 0x21, al")
        out.append("    call __io_wait")
        out.append("    mov al, 0x02")
        out.append("    out 0xA1, al")
        out.append("    call __io_wait")
        out.append("    mov al, 0x01")
        out.append("    out 0x21, al")
        out.append("    call __io_wait")
        out.append("    out 0xA1, al")
        out.append("    call __io_wait")
        out.append("    mov al, 0xF8")
        out.append("    out 0x21, al")
        out.append("    call __io_wait")
        out.append("    mov al, 0xFF")
        out.append("    out 0xA1, al")
        out.append("    call __io_wait")
        out.append("    mov al, 0x36")
        out.append("    out 0x43, al")
        out.append("    call __io_wait")
        out.append("    mov al, 0x9C")
        out.append("    out 0x40, al")
        out.append("    call __io_wait")
        out.append("    mov al, 0x2E")
        out.append("    out 0x40, al")
        out.append("    call __io_wait")
        out.append("    mov rcx, 16")
        out.append("__kbd_drain:")
        out.append("    in al, 0x64")
        out.append("    test al, 1")
        out.append("    jz __kbd_drained")
        out.append("    in al, 0x60")
        out.append("    dec rcx")
        out.append("    jne __kbd_drain")
        out.append("__kbd_drained:")
        out.append("    lidt [__idt_ptr]")
        out.append("    sti")
        out.append("    ret")
        out.append("")
        out.append("// Writes one interrupt-gate entry: rax holds the")
        out.append("// handler's address, rdi the entry's. Keeps both.")
        out.append("__idt_set:")
        out.append("    mov word ptr [rdi], ax")
        out.append("    mov word ptr [rdi + 2], 0x08")
        out.append("    mov byte ptr [rdi + 4], 0")
        out.append("    mov byte ptr [rdi + 5], 0x8E")
        out.append("    push rax")
        out.append("    shr rax, 16")
        out.append("    mov word ptr [rdi + 6], ax")
        out.append("    shr rax, 16")
        out.append("    mov dword ptr [rdi + 8], eax")
        out.append("    pop rax")
        out.append("    mov dword ptr [rdi + 12], 0")
        out.append("    ret")
        out.append("")
        out.append("// A breath between writings to the old, slow chips:")
        out.append("// a write to port 0x80, which nothing answers.")
        out.append("__io_wait:")
        out.append("    out 0x80, al")
        out.append("    ret")
        out.append("")
        out.append("__irq_default:")
        out.append("    iretq")
        out.append("")
        out.append("// The timer's knock, a hundred times a second: one")
        out.append("// more tick counted, the controller told 'seen'.")
        out.append("__irq_timer:")
        out.append("    inc qword ptr [__ticks]")
        out.append("    push rax")
        out.append("    mov al, 0x20")
        out.append("    out 0x20, al")
        out.append("    pop rax")
        out.append("    iretq")
        out.append("")
        out.append("// The keyboard's knock: the scancode waiting at port")
        out.append("// 0x60 goes into the ring buffer (64 bytes; when the")
        out.append("// ring is full the new byte is dropped — the oldest")
        out.append("// news is kept), the controller is told 'seen', and")
        out.append("// the program reads the ring with readkey().")
        out.append("__irq_keyboard:")
        out.append("    push rax")
        out.append("    push rbx")
        out.append("    push rcx")
        out.append("    in al, 0x60")
        out.append("    mov rbx, [__key_head]")
        out.append("    mov rcx, rbx")
        out.append("    sub rcx, [__key_tail]")
        out.append("    cmp rcx, 64")
        out.append("    jae __kbd_full")
        out.append("    mov rcx, rbx")
        out.append("    and rcx, 63")
        out.append("    mov byte ptr [__key_buf + rcx], al")
        out.append("    inc rbx")
        out.append("    mov [__key_head], rbx")
        out.append("__kbd_full:")
        out.append("    mov al, 0x20")
        out.append("    out 0x20, al")
        out.append("    pop rcx")
        out.append("    pop rbx")
        out.append("    pop rax")
        out.append("    iretq")
        out.append("")
        out += functionCode
        out += mainCode
        // The floor blocks, each behind its desk.
        for (index, asm) in floorBlocks.enumerated() {
            out.append("")
            out.append("__floor_\(index):")
            out.append("    push rbx")
            out.append("    push r12")
            out.append("    push r13")
            out.append("    push r14")
            out.append("    push r15")
            out.append(asm)
            out.append("    pop r15")
            out.append("    pop r14")
            out.append("    pop r13")
            out.append("    pop r12")
            out.append("    pop rbx")
            out.append("    ret")
        }
        out.append("")
        out.append("    .section .rodata")
        out.append("    .align 8")
        out.append("__gdt:")
        out.append("    .quad 0")
        out.append("    .quad 0x00AF9A000000FFFF")
        out.append("    .quad 0x00CF92000000FFFF")
        out.append("__gdt_end:")
        out.append("__gdt_ptr:")
        out.append("    .word __gdt_end - __gdt - 1")
        out.append("    .long __gdt")
        out.append("__idt_ptr:")
        out.append("    .word 4095")
        out.append("    .quad __idt")
        for literal in literals {
            out.append("\(literal.label):")
            if literal.bytes.isEmpty {
                out.append("    .byte 0")
            } else {
                out.append("    .byte " + literal.bytes.map { String($0) }.joined(separator: ", "))
            }
        }
        out.append("")
        out.append("    .section .bss")
        out.append("    .align 4096")
        out.append("__pml4:")
        out.append("    .skip 4096")
        out.append("__pdpt:")
        out.append("    .skip 4096")
        out.append("__pd:")
        out.append("    .skip 4096")
        out.append("    .align 16")
        out.append("__idt:")
        out.append("    .skip 4096")
        out.append("    .align 8")
        out.append("__ticks:")
        out.append("    .skip 8")
        out.append("__key_head:")
        out.append("    .skip 8")
        out.append("__key_tail:")
        out.append("    .skip 8")
        out.append("__key_buf:")
        out.append("    .skip 64")
        out.append("    .align 8")
        out.append("__mb_info:")
        out.append("    .skip 8")
        out.append("__mb_magic:")
        out.append("    .skip 8")
        out.append("__mem_total:")
        out.append("    .skip 8")
        out.append("__heap_cursor:")
        out.append("    .skip 8")
        out.append("__heap_limit:")
        out.append("    .skip 8")
        out.append("__guard_passes:")
        out.append("    .skip 8")
        out.append("__guard_depth:")
        out.append("    .skip 8")
        out.append("__floor_inputs:")
        out.append("    .skip 128")
        out.append("    .align 16")
        out.append("__stack:")
        out.append("    .skip 16384")
        out.append("__stack_top:")
        return out.joined(separator: "\n") + "\n"
    }

    // MARK: functions and the program

    private mutating func emitFunction(name: String, body: [Stmt]) {
        let info = functions[name]!
        scopes = [[:]]
        nextOffset = 0
        currentFunction = name
        currentExitLabel = "__fn_\(name)_exit"
        // Parameters arrive in registers, in order — rdi, rsi,
        // rdx, rcx, r8, r9, one word each (text takes two).
        let registers = ["rdi", "rsi", "rdx", "rcx", "r8", "r9"]
        var paramStores: [String] = []
        var registerIndex = 0
        for (index, param) in info.params.enumerated() {
            let kind = paramKinds[name]![index]
            let entry = declareVar(param, kind: kind == .unknown ? .number : kind)
            for slot in 0..<slots(for: entry.kind) {
                let offset = entry.offset - 8 * (slots(for: entry.kind) - 1 - slot)
                paramStores.append("    mov [rbp - \(offset)], \(registers[registerIndex])")
                registerIndex += 1
            }
        }
        let bodyStart = code.count
        for statement in body {
            emitStatement(statement)
        }
        let bodyLines = Array(code[bodyStart...])
        code = Array(code[..<bodyStart])
        let frameSize = (nextOffset + 15) / 16 * 16
        emit("__fn_\(name):")
        emit("    push rbp")
        emit("    mov rbp, rsp")
        if frameSize > 0 { emit("    sub rsp, \(frameSize)") }
        emit("    mov rax, [__guard_depth]")
        emit("    cmp rax, 500")
        emit("    jae __halt_trap")
        emit("    inc rax")
        emit("    mov [__guard_depth], rax")
        for line in paramStores { emit(line) }
        code += bodyLines
        emit("    xor eax, eax")
        emit("    xor edx, edx")
        emit("\(currentExitLabel):")
        emit("    mov rcx, [__guard_depth]")
        emit("    dec rcx")
        emit("    mov [__guard_depth], rcx")
        emit("    mov rsp, rbp")
        emit("    pop rbp")
        emit("    ret")
        emit("")
        scopes = []
        currentFunction = nil
    }

    private mutating func emitMain(_ program: [Stmt]) {
        scopes = [[:]]
        nextOffset = 0
        currentFunction = nil
        currentExitLabel = "__nifla_main_exit"
        let bodyStart = code.count
        for statement in program {
            if case .define = statement { continue }
            emitStatement(statement)
        }
        let bodyLines = Array(code[bodyStart...])
        code = Array(code[..<bodyStart])
        let frameSize = (nextOffset + 15) / 16 * 16
        emit("__nifla_main:")
        emit("    push rbp")
        emit("    mov rbp, rsp")
        if frameSize > 0 { emit("    sub rsp, \(frameSize)") }
        code += bodyLines
        emit("\(currentExitLabel):")
        emit("    mov rsp, rbp")
        emit("    pop rbp")
        emit("    ret")
        emit("")
        scopes = []
    }

    // MARK: statements

    private mutating func emitBlock(_ statements: [Stmt]) {
        scopes.append([:])
        for statement in statements {
            emitStatement(statement)
        }
        scopes.removeLast()
    }

    private mutating func emitGuardTick() {
        emit("    mov rax, [__guard_passes]")
        emit("    inc rax")
        emit("    mov [__guard_passes], rax")
        emit("    cmp rax, 1000000")
        emit("    jg __halt_trap")
    }

    private mutating func emitStatement(_ statement: Stmt) {
        switch statement {
        case .declare(let name, let value, _):
            let kind = kindOf(value)
            emitExpr(value)
            let entry = declareVar(name, kind: kind)
            emitStore(entry)

        case .assign(let name, let value, _):
            emitExpr(value)
            emitStore(lookupVar(name))

        case .assignTarget(let target, let value, _):
            // Stone 13: setting a byte in a block of bytes —
            // the one setting-by-place bare metal has. The
            // validator has proven the shape; a pick outside
            // the block, or a value that isn't a byte, stops
            // the machine.
            if case .index(let base, let index, _) = target {
                emitExpr(base)
                emit("    push rax")
                emit("    push rdx")
                emitExpr(index)
                emit("    push rax")
                emitExpr(value)
                emit("    mov r8, rax")
                emit("    pop rax")
                emit("    pop rdx")
                emit("    pop rcx")
                emit("    cmp rax, rdx")
                emit("    jae __halt_trap")
                emit("    cmp r8, 255")
                emit("    ja __halt_trap")
                emit("    mov byte ptr [rcx + rax], r8b")
            } else {
                emit("    ud2")  // fields: refused by the validator
            }

        case .say, .forEach, .attempt, .define:
            // Refused by the validator; never emitted.
            emit("    ud2")

        case .ifElse(let condition, let then, let otherwise, _):
            let elseLabel = freshLabel("else")
            let endLabel = freshLabel("endif")
            emitExpr(condition)
            emit("    test rax, rax")
            emit("    je \(otherwise != nil ? elseLabel : endLabel)")
            emitBlock(then)
            if let otherwise {
                emit("    jmp \(endLabel)")
                emit("\(elseLabel):")
                emitBlock(otherwise)
            }
            emit("\(endLabel):")

        case .whileLoop(let condition, let body, _):
            let topLabel = freshLabel("while")
            let endLabel = freshLabel("endwhile")
            emit("\(topLabel):")
            emitExpr(condition)
            emit("    test rax, rax")
            emit("    je \(endLabel)")
            emitGuardTick()
            emitBlock(body)
            emit("    jmp \(topLabel)")
            emit("\(endLabel):")

        case .repeatLoop(let count, let body, _):
            let countEntry = declareVar(freshLabel("repeat_count"), kind: .number)
            let counterEntry = declareVar(freshLabel("repeat_done"), kind: .number)
            emitExpr(count)
            emit("    mov [rbp - \(countEntry.offset)], rax")
            emit("    test rax, rax")
            emit("    js __halt_trap")
            emit("    mov qword ptr [rbp - \(counterEntry.offset)], 0")
            let topLabel = freshLabel("repeat")
            let endLabel = freshLabel("endrepeat")
            emit("\(topLabel):")
            emit("    mov rax, [rbp - \(counterEntry.offset)]")
            emit("    cmp rax, [rbp - \(countEntry.offset)]")
            emit("    jae \(endLabel)")
            emitGuardTick()
            emitBlock(body)
            emit("    mov rax, [rbp - \(counterEntry.offset)]")
            emit("    inc rax")
            emit("    mov [rbp - \(counterEntry.offset)], rax")
            emit("    jmp \(topLabel)")
            emit("\(endLabel):")

        case .give(let value, _):
            emitExpr(value)
            emit("    jmp \(currentExitLabel)")

        case .doCall(let name, let args, let line):
            emitCall(name: name, args: args, line: line)

        case .doExpr(let expr, _):
            emitExpr(expr)
        }
    }

    // Stores the value in rax (and rdx, for a two-word value —
    // text, or a block of bytes) into a variable's slot(s).
    private mutating func emitStore(_ entry: (offset: Int, kind: BareKind)) {
        if slots(for: entry.kind) == 2 {
            emit("    mov [rbp - \(entry.offset - 8)], rax")
            emit("    mov [rbp - \(entry.offset)], rdx")
        } else {
            emit("    mov [rbp - \(entry.offset)], rax")
        }
    }

    // MARK: expressions — the value lands in rax, and in rdx
    // too when it is text (rax the pointer, rdx the count).

    private mutating func emitExpr(_ expr: Expr) {
        switch expr {
        case .number(let value, _):
            emit("    mov rax, \(Int64(value))")

        case .text(let text, _):
            let label = "__text_\(literals.count)"
            literals.append((label: label, bytes: Array(text.utf8)))
            emit("    mov rax, offset \(label)")
            emit("    mov rdx, \(Array(text.utf8).count)")

        case .boolean(let flag, _):
            emit("    mov rax, \(flag ? 1 : 0)")

        case .variable(let name, _):
            let entry = lookupVar(name)
            if slots(for: entry.kind) == 2 {
                emit("    mov rax, [rbp - \(entry.offset - 8)]")
                emit("    mov rdx, [rbp - \(entry.offset)]")
            } else {
                emit("    mov rax, [rbp - \(entry.offset)]")
            }

        case .call(let name, let args, let line):
            emitCall(name: name, args: args, line: line)

        case .floor(let asm, let args, _):
            let index = floorBlocks.count
            floorBlocks.append(asm)
            var numberIndex = 0
            var hasText = false
            for arg in args {
                if slots(for: kindOf(arg)) == 2 {
                    // Text, or a block of bytes (Stone 13): both
                    // cross on the desk's memory side.
                    emitExpr(arg)
                    emit("    mov rbx, rax")
                    emit("    mov r12, rdx")
                    hasText = true
                } else {
                    emitExpr(arg)
                    emit("    mov [__floor_inputs + \(8 * numberIndex)], rax")
                    numberIndex += 1
                }
            }
            emit("    mov r10, offset __floor_inputs")
            emit("    mov r11, \(numberIndex)")
            if !hasText {
                emit("    xor ebx, ebx")
                emit("    xor r12d, r12d")
            }
            emit("    xor r13d, r13d")
            emit("    xor r14d, r14d")
            emit("    call __floor_\(index)")

        case .negate(let inner, _):
            emitExpr(inner)
            emit("    neg rax")

        case .binary(let left, let op, let right, _):
            if (op == "==" || op == "!=") && (kindOf(left) == .text || kindOf(right) == .text) {
                emitExpr(left)
                emit("    push rax")
                emit("    push rdx")
                emitExpr(right)
                emit("    mov r8, rdx")
                emit("    mov rcx, rax")
                emit("    pop rdx")
                emit("    pop rax")
                emit("    call __nifla_text_eq")
                if op == "!=" { emit("    xor rax, 1") }
                return
            }
            emitExpr(left)
            emit("    push rax")
            emitExpr(right)
            emit("    mov rcx, rax")
            emit("    pop rax")
            switch op {
            case "+": emit("    add rax, rcx")
            case "-": emit("    sub rax, rcx")
            case "*": emit("    imul rax, rcx")
            case "/":
                emit("    test rcx, rcx")
                emit("    je __halt_trap")
                emit("    cqo")
                emit("    idiv rcx")
            case "<": emitCompare("setl")
            case "<=": emitCompare("setle")
            case ">": emitCompare("setg")
            case ">=": emitCompare("setge")
            case "==": emitCompare("sete")
            case "!=": emitCompare("setne")
            default: emit("    ud2")
            }

        case .index(let base, let index, _):
            // Stone 13: reading a byte from a block of bytes —
            // the one indexing bare metal has. The validator
            // has proven the base is a block of bytes; a pick
            // outside it stops the machine.
            emitExpr(base)
            emit("    push rax")
            emit("    push rdx")
            emitExpr(index)
            emit("    pop rdx")
            emit("    pop rcx")
            emit("    cmp rax, rdx")
            emit("    jae __halt_trap")
            emit("    movzx rax, byte ptr [rcx + rax]")

        case .object, .list, .field:
            emit("    ud2")  // refused by the validator
        }
    }

    private mutating func emitCompare(_ setcc: String) {
        emit("    cmp rax, rcx")
        emit("    \(setcc) al")
        emit("    movzx rax, al")
    }

    // A call: values are worked out in order, stacked, and
    // popped into the registers — rdi, rsi, rdx, rcx, r8, r9 —
    // then the function is called. 'length' is the one tool:
    // the text is already in rax/rdx, so its count is the
    // answer.
    private mutating func emitCall(name: String, args: [Expr], line: Int) {
        if name == "length" {
            emitExpr(args[0])
            emit("    mov rax, rdx")
            return
        }
        if name == "makebytes" {
            // Stone 13: the allocator answers with the block's
            // address in rax and its count in rdx — the same
            // two words a piece of text travels in.
            emitExpr(args[0])
            emit("    call __nifla_alloc")
            return
        }
        // The bare-only tools (Stones 12 and 13): reads of the
        // machine itself, emitted where the call stands.
        if name == "memorysize" {
            emit("    mov rax, [__mem_total]")
            return
        }
        if name == "ticks" {
            emit("    mov rax, [__ticks]")
            return
        }
        if name == "waittick" {
            // Sleep until the next interrupt — the timer's, at
            // the latest — then hand back the tick count.
            emit("    hlt")
            emit("    mov rax, [__ticks]")
            return
        }
        if name == "readkey" {
            // The keyboard buffer's next scancode, or 0 when
            // no key is waiting. The buffer is filled by the
            // keyboard interrupt and emptied here — one
            // producer, one consumer; a keystroke landing in
            // the middle of this read is picked up next time.
            let emptyLabel = freshLabel("readkey_empty")
            let doneLabel = freshLabel("readkey_done")
            emit("    mov rax, [__key_tail]")
            emit("    cmp rax, [__key_head]")
            emit("    je \(emptyLabel)")
            emit("    mov rcx, rax")
            emit("    and ecx, 63")
            emit("    movzx ecx, byte ptr [__key_buf + rcx]")
            emit("    inc rax")
            emit("    mov [__key_tail], rax")
            emit("    mov rax, rcx")
            emit("    jmp \(doneLabel)")
            emit("\(emptyLabel):")
            emit("    xor eax, eax")
            emit("\(doneLabel):")
            return
        }
        let registers = ["rdi", "rsi", "rdx", "rcx", "r8", "r9"]
        var slotCount = 0
        for arg in args {
            emitExpr(arg)
            emit("    push rax")
            slotCount += 1
            if slots(for: kindOf(arg)) == 2 {
                emit("    push rdx")
                slotCount += 1
            }
        }
        if slotCount > 0 {
            for index in stride(from: slotCount - 1, through: 0, by: -1) {
                emit("    pop \(registers[index])")
            }
        }
        emit("    call __fn_\(name)")
    }
}

// MARK: - Building the bare binary

private func findTool(_ candidates: [String]) -> String? {
    for candidate in candidates {
        if FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }
    }
    return nil
}

// Runs a build tool; gives back its exit status and what it
// said on its error channel.
private func runTool(_ path: String, _ arguments: [String]) -> (status: Int32, words: String)? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    let errorPipe = Pipe()
    process.standardError = errorPipe
    process.standardOutput = Pipe()
    do {
        try process.run()
    } catch {
        return nil
    }
    process.waitUntilExit()
    let words = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    return (process.terminationStatus, words)
}

// niflac --bare: validate the subset, translate to assembly,
// assemble, link at 0x100000 with the multiboot section first,
// and repackage the linked 64-bit ELF in a 32-bit ELF shell —
// the form QEMU's built-in multiboot loader accepts (every
// address in the binary is below 4 GiB, so nothing is lost;
// GRUB reads either form). The assembly is kept beside the
// binary, like the hosted path keeps its Swift and floor
// assembly.
func compileBare(inputPath: String, output: String?, program: [Stmt], fail: (String, Int32) -> Int32) -> Int32 {
    let validator = BareValidator()
    do {
        try validator.validate(program)
    } catch let error as NiflaError {
        return fail(error.spoken, 1)
    } catch {
        return fail("Something went wrong while reading the program.", 1)
    }

    var translator = BareTranslator(validator: validator)
    let asm = translator.translate(program, sourceName: URL(fileURLWithPath: inputPath).lastPathComponent)

    let outputPath: String
    if let output {
        outputPath = output
    } else {
        outputPath = URL(fileURLWithPath: inputPath).deletingPathExtension().path + ".elf"
    }
    let asmPath = outputPath + ".s"
    do {
        try asm.write(toFile: asmPath, atomically: true, encoding: .utf8)
    } catch {
        return fail("I couldn't write the assembly to '\(asmPath)'.", 2)
    }

    guard let cc = findAssembler() else {
        return fail("I couldn't find an assembler (cc) to build the bare program with. Install a C compiler toolchain and try again.", 2)
    }
    guard let ld = findTool(["/usr/bin/ld", "/bin/ld", "/usr/local/bin/ld"]) else {
        return fail("I couldn't find a linker (ld) to build the bare program with.", 2)
    }
    guard let objcopy = findTool(["/usr/bin/objcopy", "/bin/objcopy", "/usr/local/bin/objcopy"]) else {
        return fail("I couldn't find objcopy, which the bare build uses to package the binary for multiboot loaders.", 2)
    }

    let scratch = FileManager.default.temporaryDirectory
        .appendingPathComponent("niflac-bare-\(ProcessInfo.processInfo.processIdentifier)")
    do {
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    } catch {
        return fail("I couldn't set up a scratch folder to build in.", 2)
    }
    defer { try? FileManager.default.removeItem(at: scratch) }

    let linkerScript = """
        ENTRY(_start32)
        SECTIONS {
            . = 0x100000;
            .multiboot : { *(.multiboot) }
            .text : { *(.text) }
            .rodata : { *(.rodata) }
            .data : { *(.data) }
            .bss : { *(.bss) *(COMMON) }
            . = ALIGN(4096);
            __kernel_end = .;
        }
        """
    let scriptPath = scratch.appendingPathComponent("bare.ld").path
    let objectPath = scratch.appendingPathComponent("bare.o").path
    let linkedPath = scratch.appendingPathComponent("bare64.elf").path
    do {
        try linkerScript.write(toFile: scriptPath, atomically: true, encoding: .utf8)
    } catch {
        return fail("I couldn't set up a scratch folder to build in.", 2)
    }

    guard let assembled = runTool(cc, ["-c", asmPath, "-o", objectPath]) else {
        return fail("I couldn't start the assembler at '\(cc)'.", 2)
    }
    if assembled.status != 0 {
        return fail("The bare program in '\(inputPath)' couldn't be assembled. What the assembler said:\n\(assembled.words)", 1)
    }
    guard let linked = runTool(ld, ["-m", "elf_x86_64", "-T", scriptPath, objectPath, "-o", linkedPath]) else {
        return fail("I couldn't start the linker at '\(ld)'.", 2)
    }
    if linked.status != 0 {
        return fail("The bare program in '\(inputPath)' couldn't be linked. What the linker said:\n\(linked.words)", 1)
    }
    guard let packaged = runTool(objcopy, ["-O", "elf32-i386", linkedPath, outputPath]) else {
        return fail("I couldn't start objcopy at '\(objcopy)'.", 2)
    }
    if packaged.status != 0 {
        return fail("The bare program in '\(inputPath)' couldn't be packaged. What objcopy said:\n\(packaged.words)", 1)
    }

    print("Made \(outputPath) — a bare-metal program, compiled from \(inputPath). It boots on its own: no operating system underneath.")
    print("The assembly it was made from is kept at \(asmPath), if you'd like to read it.")
    return 0
}
