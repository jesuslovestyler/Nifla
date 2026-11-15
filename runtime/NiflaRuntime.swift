// Nifla — Stone 5: the runtime that compiled programs carry.
//
// When niflac compiles a Nifla program, it translates the program
// into Swift and compiles it together with this file. Everything
// here mirrors the interpreter's values and rules — the same kinds,
// the same plain-words errors, the same guards — so a compiled
// program behaves exactly as the interpreter would have run it,
// line for line. The difference is only in how it runs: native
// code, no interpreter involved.
//
// Part of Nifla, a public-domain programming language by Tyler
// Kovalevich. See the Unlicense in the LICENSE file at the root of
// this repository.

import Foundation

// An error in plain words — the same shape the interpreter uses.
struct NiflaError: Error {
    let line: Int
    let message: String
    var spoken: String { "Line \(line): \(message)" }
}

// How a number is written out for people: whole numbers without a
// trailing ".0", decimals plainly.
func formatNumber(_ value: Double) -> String {
    if value == value.rounded() && abs(value) < 1e15 {
        return String(Int(value))
    }
    return String(value)
}

// An object: named fields, kept in the order they were first
// written. A class on purpose — objects are shared by reference,
// the way JavaScript's are.
final class NiflaObject {
    private(set) var fieldNames: [String] = []
    private var values: [String: Value] = [:]

    func value(for name: String) -> Value? {
        values[name]
    }

    func set(_ name: String, _ value: Value) {
        if values[name] == nil { fieldNames.append(name) }
        values[name] = value
    }

    // Takes a field out (Stone 10): hands back the value it held,
    // or nil when the object has no such field.
    func remove(_ name: String) -> Value? {
        guard let value = values[name] else { return nil }
        values[name] = nil
        fieldNames.removeAll { $0 == name }
        return value
    }
}

// A list (Stone 6): values in order, in a class on purpose —
// lists are shared by reference, the way objects are.
final class NiflaList {
    var items: [Value] = []

    init(items: [Value] = []) {
        self.items = items
    }
}

// A block of bytes (Stone 9): raw memory, a fixed number of
// bytes, each a whole number from 0 to 255. A class on purpose —
// shared by reference, so a floor block handed the block works
// on the very memory the high-level side reads back afterwards.
final class NiflaBytes {
    var data: [UInt8]

    init(count: Int) {
        data = [UInt8](repeating: 0, count: count)
    }
}

enum Value {
    case number(Double)
    case text(String)
    case boolean(Bool)
    case object(NiflaObject)
    case list(NiflaList)
    case bytes(NiflaBytes)

    // How the value is shown by `say`.
    var spoken: String {
        render(seen: [], quoted: false)
    }

    private func render(seen: Set<ObjectIdentifier>, quoted: Bool) -> String {
        switch self {
        case .number(let value): return formatNumber(value)
        case .text(let value): return quoted ? "\"\(value)\"" : value
        case .boolean(let value): return value ? "true" : "false"
        case .object(let object):
            let id = ObjectIdentifier(object)
            if seen.contains(id) { return "..." }
            if object.fieldNames.isEmpty { return "{ }" }
            var inner = seen
            inner.insert(id)
            let parts = object.fieldNames.map { name in
                "\(name): \(object.value(for: name)!.render(seen: inner, quoted: true))"
            }
            return "{ " + parts.joined(separator: ", ") + " }"
        case .list(let list):
            let id = ObjectIdentifier(list)
            if seen.contains(id) { return "..." }
            if list.items.isEmpty { return "[]" }
            var inner = seen
            inner.insert(id)
            let parts = list.items.map { $0.render(seen: inner, quoted: true) }
            return "[" + parts.joined(separator: ", ") + "]"
        case .bytes(let bytes):
            let parts = bytes.data.map { String($0) }
            return "bytes(" + parts.joined(separator: ", ") + ")"
        }
    }

    // How the value is described inside an error message.
    var described: String {
        switch self {
        case .number(let value): return "the number \(formatNumber(value))"
        case .text(let value): return "the text \"\(value)\""
        case .boolean(let value): return value ? "true" : "false"
        case .object(let object):
            if object.fieldNames.isEmpty { return "an object with no fields yet" }
            return "an object with the fields \(object.fieldNames.joined(separator: ", "))"
        case .list(let list):
            switch list.items.count {
            case 0: return "an empty list"
            case 1: return "a list of 1 item"
            default: return "a list of \(list.items.count) items"
            }
        case .bytes(let bytes):
            switch bytes.data.count {
            case 0: return "an empty block of bytes"
            case 1: return "a block of 1 byte"
            default: return "a block of \(bytes.data.count) bytes"
            }
        }
    }
}

// One scope of variables, linked to the scope around it — the same
// shape the interpreter uses.
final class Scope {
    private var values: [String: Value] = [:]
    private let parent: Scope?

    init(parent: Scope? = nil) {
        self.parent = parent
    }

    func lookup(_ name: String) -> Value? {
        values[name] ?? parent?.lookup(name)
    }

    func isDeclaredHere(_ name: String) -> Bool {
        values[name] != nil
    }

    func declare(_ name: String, _ value: Value) {
        values[name] = value
    }

    func assign(_ name: String, _ value: Value) -> Bool {
        if values[name] != nil {
            values[name] = value
            return true
        }
        return parent?.assign(name, value) ?? false
    }

    func allNames() -> [String] {
        var names = Array(values.keys)
        if let parent { names += parent.allNames() }
        return names
    }
}

// Edit distance between two words, for spelling suggestions.
func editDistance(_ a: String, _ b: String) -> Int {
    let aChars = Array(a)
    let bChars = Array(b)
    if aChars.isEmpty { return bChars.count }
    if bChars.isEmpty { return aChars.count }
    var previous = Array(0...bChars.count)
    var current = [Int](repeating: 0, count: bChars.count + 1)
    for i in 1...aChars.count {
        current[0] = i
        for j in 1...bChars.count {
            let cost = aChars[i - 1] == bChars[j - 1] ? 0 : 1
            current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
        }
        swap(&previous, &current)
    }
    return previous[bChars.count]
}

// How a 'give' line hands its value back: thrown, and caught by the
// call that is running the function.
struct NiflaReturn: Error {
    let value: Value
}

// A built-in tool (Stone 6): a function every Nifla program has
// from the start, without making it. `params` names the values it
// takes, for plain-words messages; `example` shows a call to it.
// This table is the runtime's own copy of the interpreter's, and
// the two must agree.
struct BuiltinDef {
    let params: [String]
    let example: String
}

let builtinTools: [String: BuiltinDef] = [
    "length": BuiltinDef(params: ["value"], example: "length(\"Tyler\")"),
    "join": BuiltinDef(params: ["list", "separator"], example: "join(words, \" \")"),
    "split": BuiltinDef(params: ["text", "separator"], example: "split(\"a,b\", \",\")"),
    "part": BuiltinDef(params: ["text", "start", "count"], example: "part(\"Tyler\", 0, 2)"),
    "find": BuiltinDef(params: ["text", "piece"], example: "find(\"Tyler\", \"y\")"),
    "append": BuiltinDef(params: ["list", "value"], example: "append(items, 4)"),
    "readfile": BuiltinDef(params: ["path"], example: "readfile(\"notes.txt\")"),
    "writefile": BuiltinDef(params: ["path", "text"], example: "writefile(\"notes.txt\", \"Shalom\")"),
    "arguments": BuiltinDef(params: [], example: "arguments()"),
    "makebytes": BuiltinDef(params: ["count"], example: "makebytes(8)"),
    "sayerr": BuiltinDef(params: ["value"], example: "sayerr(\"Mind the step.\")"),
    "exitwith": BuiltinDef(params: ["code"], example: "exitwith(1)"),
    "removeat": BuiltinDef(params: ["list", "index"], example: "removeat(items, 0)"),
    "insertat": BuiltinDef(params: ["list", "index", "value"], example: "insertat(items, 0, 4)"),
    "sorted": BuiltinDef(params: ["list"], example: "sorted(items)"),
    "fieldnames": BuiltinDef(params: ["object"], example: "fieldnames(person)"),
    "removefield": BuiltinDef(params: ["object", "name"], example: "removefield(person, \"town\")"),
]

// The plain-words message for a call to a built-in tool with the
// wrong number of values.
func builtinCountMessage(name: String, def: BuiltinDef, given: Int) -> String {
    let takes: String
    switch def.params.count {
    case 0: takes = "no values"
    case 1: takes = "1 value (\(def.params[0]))"
    default: takes = "\(def.params.count) values (\(def.params.joined(separator: ", ")))"
    }
    return "The tool '\(name)' takes \(takes), but it was given \(given). Call it like: \(def.example)."
}

// The place an item-setting line will write to: what a list
// slot and a bytes slot (Stone 9) have in common.
protocol ItemSlot {
    func set(_ value: Value) throws
}

// The place an item-setting line will write to: a list and the
// item's number in it, checked and ready.
struct ListSlot: ItemSlot {
    let list: NiflaList
    let index: Int

    func set(_ value: Value) throws {
        list.items[index] = value
    }
}

// The place a byte-setting line will write to (Stone 9): a block
// of bytes and the byte's number in it, checked and ready. The
// value itself is checked when it is stored — a byte must be a
// whole number from 0 to 255.
struct BytesSlot: ItemSlot {
    let bytes: NiflaBytes
    let index: Int
    let line: Int

    func set(_ value: Value) throws {
        bytes.data[index] = try Machine.byteValue(value, line: line)
    }
}

// A function made with 'make': the names it takes, the scope it was
// made in (its home), and its body as compiled Swift code.
struct FunctionDef {
    let params: [String]
    let home: Scope
    let body: (Machine, Scope) throws -> Void
}

// The machine a compiled program runs on: the functions made so
// far, and the two kindness guards (loop passes, call depth), with
// the interpreter's own plain words for every problem.
final class Machine {
    private var loopPasses = 0
    private let loopPassLimit = 1_000_000

    private var functions: [String: FunctionDef] = [:]

    private var callDepth = 0
    private let callDepthLimit = 500

    // The words handed to this program when it was started, after
    // the program's own name — what arguments() gives (Stone 6).
    let programArguments: [String] = Array(CommandLine.arguments.dropFirst())

    // What 'say' does in a compiled program: the value's spoken
    // form and a new line, written straight to standard output —
    // not buffered — so that in a program with floor blocks
    // (Stone 7), whose raw writes are never buffered, everything
    // the program says comes out in the order it was said.
    func say(_ value: Value) {
        FileHandle.standardOutput.write(Data((value.spoken + "\n").utf8))
    }

    func tickLoop(line: Int) throws {
        loopPasses += 1
        if loopPasses > loopPassLimit {
            throw NiflaError(line: line, message: "This loop ran more than a million times and was stopped — it may never end. Check the condition, and make sure something inside the loop changes each time around, so it can finish.")
        }
    }

    // --- variables -------------------------------------------------

    // The first half of a 'let' line: the interpreter checks for a
    // name already made in this block before it works the value out,
    // so the compiled program does the same, in the same order.
    func checkDeclare(_ name: String, in scope: Scope, line: Int) throws {
        if scope.isDeclaredHere(name) {
            throw NiflaError(line: line, message: "There is already a variable called '\(name)' in this block. To change what it holds, write: \(name) = ...")
        }
    }

    func lookup(_ name: String, in scope: Scope, line: Int) throws -> Value {
        if let value = scope.lookup(name) {
            return value
        }
        var message = "I don't know a variable called '\(name)' yet. You can make one with: let \(name) = ..."
        if let suggestion = closestName(to: name, in: scope) {
            message += " Did you mean '\(suggestion)'?"
        }
        throw NiflaError(line: line, message: message)
    }

    func assign(_ name: String, _ value: Value, in scope: Scope, line: Int) throws {
        if !scope.assign(name, value) {
            throw NiflaError(line: line, message: "I can't set '\(name)', because no variable called '\(name)' has been made yet. Make one first with: let \(name) = ...")
        }
    }

    // --- objects ---------------------------------------------------

    func makeObject(_ fields: [(String, Value)]) -> Value {
        let object = NiflaObject()
        for (name, value) in fields {
            object.set(name, value)
        }
        return .object(object)
    }

    func readField(_ base: Value, _ name: String, line: Int) throws -> Value {
        guard case .object(let object) = base else {
            throw NiflaError(line: line, message: "I can't read the field '\(name)' of \(base.described), because only an object has fields. Make an object first, like: let person = { name: \"Tyler\" } — then person.name works.")
        }
        guard let value = object.value(for: name) else {
            throw missingFieldError(object: object, field: name, line: line)
        }
        return value
    }

    // For a field-setting line: the object whose field is being set,
    // checked before the new value is worked out, as the
    // interpreter does.
    func fieldTarget(_ base: Value, _ name: String, line: Int) throws -> NiflaObject {
        guard case .object(let object) = base else {
            throw NiflaError(line: line, message: "I can't set the field '\(name)' on \(base.described), because only an object has fields. Make an object first, like: let person = { name: \"Tyler\" } — then person.\(name) = ... works.")
        }
        return object
    }

    // --- lists (Stone 6) -------------------------------------------

    func makeList(_ items: [Value]) -> Value {
        .list(NiflaList(items: items))
    }

    // Checks that a value can pick an item: a whole number.
    func itemNumber(_ value: Value, line: Int) throws -> Int {
        guard case .number(let number) = value else {
            throw NiflaError(line: line, message: "I can't use \(value.described) to pick an item. Items are picked by a whole number — 0 for the first one, 1 for the second, and so on.")
        }
        guard number == number.rounded() && abs(number) < 1e15 else {
            throw NiflaError(line: line, message: "An item number must be a whole number, but I was given \(formatNumber(number)). Use a whole number, like 0, 1, or 2.")
        }
        return Int(number)
    }

    // Reads one item of a list, or one character of some text.
    func readIndex(_ base: Value, _ indexValue: Value, line: Int) throws -> Value {
        switch base {
        case .list(let list):
            let index = try itemNumber(indexValue, line: line)
            if list.items.isEmpty {
                throw NiflaError(line: line, message: "This list has no items yet, so there is no item \(index) to take from it. Items can be added with append — like: append(items, ...).")
            }
            guard index >= 0 && index < list.items.count else {
                throw NiflaError(line: line, message: "This list has \(list.items.count) items, numbered 0 to \(list.items.count - 1), but I was asked for item \(index).")
            }
            return list.items[index]

        case .text(let text):
            let index = try itemNumber(indexValue, line: line)
            let chars = Array(text)
            if chars.isEmpty {
                throw NiflaError(line: line, message: "This text has no characters yet, so there is no character \(index) to take from it.")
            }
            guard index >= 0 && index < chars.count else {
                throw NiflaError(line: line, message: "This text has \(chars.count) characters, numbered 0 to \(chars.count - 1), but I was asked for character \(index).")
            }
            return .text(String(chars[index]))

        case .bytes(let bytes):
            let index = try itemNumber(indexValue, line: line)
            if bytes.data.isEmpty {
                throw NiflaError(line: line, message: "This block of bytes has no bytes yet, so there is no byte \(index) to take from it. Make a bigger block with makebytes — like: makebytes(8).")
            }
            guard index >= 0 && index < bytes.data.count else {
                throw NiflaError(line: line, message: "This block of bytes has \(bytes.data.count) bytes, numbered 0 to \(bytes.data.count - 1), but I was asked for byte \(index).")
            }
            return .number(Double(bytes.data[index]))

        default:
            throw NiflaError(line: line, message: "I can't take an item from \(base.described). Only a list or some text has items to take from — like [1, 2, 3], where [0] takes the first item, or \"abc\", where [0] takes the first character.")
        }
    }

    // For an item-setting line: the list and number the line will
    // write to, checked before the new value is worked out, as the
    // interpreter checks them.
    func indexTarget(_ base: Value, _ indexValue: Value, line: Int) throws -> ItemSlot {
        switch base {
        case .list(let list):
            let index = try itemNumber(indexValue, line: line)
            if list.items.isEmpty {
                throw NiflaError(line: line, message: "This list has no items yet, so there is no item \(index) to set. To add an item at the end, use append — like: append(items, ...).")
            }
            guard index >= 0 && index < list.items.count else {
                throw NiflaError(line: line, message: "This list has \(list.items.count) items, numbered 0 to \(list.items.count - 1), so there is no item \(index) to set. To add an item at the end, use append — like: append(items, ...).")
            }
            return ListSlot(list: list, index: index)
        case .bytes(let bytes):
            let index = try itemNumber(indexValue, line: line)
            if bytes.data.isEmpty {
                throw NiflaError(line: line, message: "This block of bytes has no bytes yet, so there is no byte \(index) to set. Make a bigger block with makebytes — like: makebytes(8).")
            }
            guard index >= 0 && index < bytes.data.count else {
                throw NiflaError(line: line, message: "This block of bytes has \(bytes.data.count) bytes, numbered 0 to \(bytes.data.count - 1), so there is no byte \(index) to set.")
            }
            return BytesSlot(bytes: bytes, index: index, line: line)
        case .text:
            throw NiflaError(line: line, message: "I can't change one character of some text — once text is made, it doesn't change. To change it, build the new text and set the variable to it instead.")
        default:
            throw NiflaError(line: line, message: "I can only set an item in a list, like: items[0] = 30 — but this is \(base.described), which has no items to set.")
        }
    }

    // The items a 'for' loop walks: a list's items as they stand
    // when the loop begins, a text's characters one by one, or a
    // block of bytes' bytes as numbers (Stone 9).
    func forItems(_ value: Value, line: Int) throws -> [Value] {
        switch value {
        case .list(let list):
            return list.items
        case .text(let text):
            return Array(text).map { Value.text(String($0)) }
        case .bytes(let bytes):
            return bytes.data.map { Value.number(Double($0)) }
        default:
            throw NiflaError(line: line, message: "'for' needs a list, some text, or a block of bytes to walk through, but here it was given \(value.described). Write it like: for item in items { ... }")
        }
    }

    private func missingFieldError(object: NiflaObject, field name: String, line: Int) -> NiflaError {
        if object.fieldNames.isEmpty {
            return NiflaError(line: line, message: "This object has no fields yet, so it has no field called '\(name)'. You can add one by setting it, like: person.\(name) = ...")
        }
        var message = "This object has no field called '\(name)'. Its fields are: \(object.fieldNames.joined(separator: ", "))."
        if let suggestion = closestFieldName(to: name, in: object) {
            message += " Did you mean '\(suggestion)'?"
        }
        return NiflaError(line: line, message: message)
    }

    // --- the Floor (Stones 7 and 9) --------------------------------

    // Checks that a value can be stored in a block of bytes: a
    // whole number from 0 to 255.
    static func byteValue(_ value: Value, line: Int) throws -> UInt8 {
        guard case .number(let number) = value, number == number.rounded(), number >= 0, number <= 255 else {
            throw NiflaError(line: line, message: "A byte is a whole number from 0 to 255, but I was given \(value.described).")
        }
        return UInt8(number)
    }

    // Runs one floor block (Stone 9's desk): the values the block
    // was handed are checked and laid out — the whole numbers in
    // an array the block reads through r10/r11, the one block of
    // bytes as the very memory the block works on through
    // rbx/r12, and a results area (room for eight numbers) the
    // block writes extra answers into through r13, saying how
    // many with r14. The generated code hands over a closure that
    // calls the block's own assembly with those pointers.
    //
    // What the block gives back: the number its instructions
    // leave in rax, as since Stone 7 — or, when it wrote extra
    // answers, a list: the rax number first, then the extras in
    // the order it wrote them.
    func runFloor(args: [Value], line: Int, call: (UnsafePointer<Int64>?, Int64, UnsafeMutablePointer<UInt8>?, Int64, UnsafeMutablePointer<Int64>, UnsafeMutablePointer<Int64>) -> Int64) throws -> Value {
        var inputs: [Int64] = []
        var memory: NiflaBytes? = nil
        for arg in args {
            switch arg {
            case .number(let number):
                guard number == number.rounded() && abs(number) < 1e15 else {
                    throw NiflaError(line: line, message: "A floor block can be handed only whole numbers, but it was handed \(arg.described).")
                }
                inputs.append(Int64(number))
            case .bytes(let bytes):
                if memory != nil {
                    throw NiflaError(line: line, message: "A floor block can be handed only one block of bytes, but it was handed two.")
                }
                memory = bytes
            default:
                throw NiflaError(line: line, message: "A floor block can be handed numbers and one block of bytes, but it was given \(arg.described).")
            }
        }
        var results = [Int64](repeating: 0, count: 8)
        var resultCount: Int64 = 0
        let inputCount = Int64(inputs.count)
        let memoryCount = Int64(memory?.data.count ?? 0)
        let headline: Int64 = results.withUnsafeMutableBufferPointer { resultsBuffer in
            withUnsafeMutablePointer(to: &resultCount) { countPointer in
                inputs.withUnsafeBufferPointer { inputsBuffer in
                    if let memory {
                        return memory.data.withUnsafeMutableBufferPointer { memoryBuffer in
                            call(inputsBuffer.baseAddress, inputCount,
                                 memoryBuffer.baseAddress, memoryCount,
                                 resultsBuffer.baseAddress!, countPointer)
                        }
                    }
                    return call(inputsBuffer.baseAddress, inputCount,
                                nil, 0,
                                resultsBuffer.baseAddress!, countPointer)
                }
            }
        }
        let extra = Int(max(0, min(8, resultCount)))
        if extra == 0 {
            return .number(Double(headline))
        }
        let list = NiflaList()
        list.items.append(.number(Double(headline)))
        for index in 0..<extra {
            list.items.append(.number(Double(results[index])))
        }
        return .list(list)
    }

    // --- operators -------------------------------------------------

    func negate(_ value: Value, line: Int) throws -> Value {
        guard case .number(let number) = value else {
            throw NiflaError(line: line, message: "I can only put a minus sign in front of a number, but here it was in front of \(value.described).")
        }
        return .number(-number)
    }

    func apply(_ op: String, _ left: Value, _ right: Value, line: Int) throws -> Value {
        switch op {
        case "+":
            if case .text = left {
                return .text(left.spoken + right.spoken)
            }
            if case .text = right {
                return .text(left.spoken + right.spoken)
            }
            if case .number(let a) = left, case .number(let b) = right {
                return .number(a + b)
            }
            throw NiflaError(line: line, message: "I can't add \(left.described) and \(right.described). '+' adds two numbers, or joins text together.")

        case "-", "*", "/":
            guard case .number(let a) = left, case .number(let b) = right else {
                let verb = op == "-" ? "subtract" : (op == "*" ? "multiply" : "divide")
                throw NiflaError(line: line, message: "I can't \(verb) \(left.described) and \(right.described). '\(op)' works on two numbers. (Only '+' joins text.)")
            }
            switch op {
            case "-": return .number(a - b)
            case "*": return .number(a * b)
            default:
                if b == 0 {
                    throw NiflaError(line: line, message: "I can't divide by zero. Dividing needs a second number that isn't zero.")
                }
                return .number(a / b)
            }

        case "==", "!=":
            let equal: Bool
            switch (left, right) {
            case (.number(let a), .number(let b)): equal = a == b
            case (.text(let a), .text(let b)): equal = a == b
            case (.boolean(let a), .boolean(let b)): equal = a == b
            case (.object(let a), .object(let b)): equal = a === b
            case (.list(let a), .list(let b)): equal = a === b
            case (.bytes(let a), .bytes(let b)): equal = a === b
            default: equal = false
            }
            return .boolean(op == "==" ? equal : !equal)

        case "<", "<=", ">", ">=":
            guard case .number(let a) = left, case .number(let b) = right else {
                throw NiflaError(line: line, message: "I can't compare \(left.described) and \(right.described) with '\(op)'. '\(op)' compares two numbers. (Text and true/false values can be checked with == and !=.)")
            }
            switch op {
            case "<": return .boolean(a < b)
            case "<=": return .boolean(a <= b)
            case ">": return .boolean(a > b)
            default: return .boolean(a >= b)
            }

        default:
            throw NiflaError(line: line, message: "I don't know the sign '\(op)'.")
        }
    }

    // --- decisions and loops ----------------------------------------

    // The deciding value of an 'if' or 'while', checked the way the
    // interpreter checks it.
    func decide(_ value: Value, kind: String, line: Int) throws -> Bool {
        guard case .boolean(let flag) = value else {
            if kind == "if" {
                throw NiflaError(line: line, message: "'if' needs a true or false value to decide with, but here it was given \(value.described). Try a comparison, like: if years > 12 { ... }")
            }
            throw NiflaError(line: line, message: "'while' needs a true or false value to decide with, but here it was given \(value.described). Try a comparison, like: while years < 40 { ... }")
        }
        return flag
    }

    // A 'repeat' count, worked out and checked the way the
    // interpreter checks it.
    func repeatCount(_ value: Value, line: Int) throws -> Double {
        guard case .number(let count) = value else {
            throw NiflaError(line: line, message: "'repeat' needs a number saying how many times to run, but here it was given \(value.described). Write it like: repeat 3 { ... }")
        }
        if count < 0 {
            throw NiflaError(line: line, message: "'repeat' was told to run \(formatNumber(count)) times, but a count can't be negative — a loop can't run less than zero times. Use zero or more, like: repeat 3 { ... }")
        }
        if count != count.rounded() {
            throw NiflaError(line: line, message: "'repeat' was told to run \(formatNumber(count)) times, but a loop can only run a whole number of times. Use a whole number instead, like \(formatNumber(count.rounded(.down))) or \(formatNumber(count.rounded(.up))).")
        }
        return count
    }

    // --- functions ---------------------------------------------------

    func define(_ name: String, params: [String], home: Scope, line: Int, body: @escaping (Machine, Scope) throws -> Void) throws {
        if builtinTools[name] != nil {
            throw NiflaError(line: line, message: "There is already a built-in tool called '\(name)' — every Nifla program has it from the start. A function can't be made with that name; rename the function.")
        }
        if functions[name] != nil {
            throw NiflaError(line: line, message: "There is already a function called '\(name)'. Each function needs its own name — rename this one, or take out the earlier 'make \(name)'.")
        }
        functions[name] = FunctionDef(params: params, home: home, body: body)
    }

    // A 'give' line outside any function.
    func giveOutside(line: Int) throws -> Never {
        throw NiflaError(line: line, message: "'give' hands a value back from a function to whoever called it, but this line is not inside a function. To show a value here, use 'say' instead.")
    }

    // A call used inside an expression: it must give a value back.
    func callValue(_ name: String, args: [() throws -> Value], line: Int) throws -> Value {
        guard let value = try callFunction(name: name, argExprs: args, line: line) else {
            throw NiflaError(line: line, message: "The function '\(name)' finished without giving a value back, so there is nothing to use here. Add a 'give' line inside '\(name)', or call it on its own line instead.")
        }
        return value
    }

    // A call on its own line: run for what it does; any value it
    // gives back is simply not used.
    func callStatement(_ name: String, args: [() throws -> Value], line: Int) throws {
        _ = try callFunction(name: name, argExprs: args, line: line)
    }

    // Runs one call, in the interpreter's own order: a built-in
    // tool first (every program has them); for a made function, the
    // function must exist, then the handed values are worked out,
    // then their number is checked, then the depth guard, then the
    // body runs in a fresh scope inside the function's home.
    private func callFunction(name: String, argExprs: [() throws -> Value], line: Int) throws -> Value? {
        if let builtin = builtinTools[name] {
            let args = try argExprs.map { try $0() }
            guard args.count == builtin.params.count else {
                throw NiflaError(line: line, message: builtinCountMessage(name: name, def: builtin, given: args.count))
            }
            return try runBuiltin(name, args: args, line: line)
        }
        guard let def = functions[name] else {
            var message = "I don't know a function called '\(name)' yet. You can make one with: make \(name)(...) { ... }"
            if let suggestion = closestFunctionName(to: name) {
                message += " Did you mean '\(suggestion)'?"
            }
            throw NiflaError(line: line, message: message)
        }
        let args = try argExprs.map { try $0() }
        guard args.count == def.params.count else {
            throw NiflaError(line: line, message: "The function '\(name)' takes \(takesText(def.params)), but it was given \(args.count). Make the call match how the function was made: \(name)(\(def.params.joined(separator: ", "))).")
        }
        guard callDepth < callDepthLimit else {
            throw NiflaError(line: line, message: "This call is more than five hundred functions deep and was stopped — it may never finish. A function that calls itself needs a way to stop, like an 'if' that gives an answer for the smallest case instead of calling again.")
        }
        callDepth += 1
        defer { callDepth -= 1 }
        let callScope = Scope(parent: def.home)
        for (param, arg) in zip(def.params, args) {
            callScope.declare(param, arg)
        }
        do {
            try def.body(self, callScope)
        } catch let signal as NiflaReturn {
            return signal.value
        }
        return nil
    }

    private func takesText(_ params: [String]) -> String {
        switch params.count {
        case 0: return "no values"
        case 1: return "1 value (\(params[0]))"
        default: return "\(params.count) values (\(params.joined(separator: ", ")))"
        }
    }

    private func closestFunctionName(to name: String) -> String? {
        var best: (name: String, distance: Int)? = nil
        for candidate in Array(functions.keys) + Array(builtinTools.keys) where candidate != name {
            let distance = editDistance(name, candidate)
            if distance <= 2 && (best == nil || distance < best!.distance) {
                best = (candidate, distance)
            }
        }
        return best?.name
    }

    // Runs a built-in tool (Stone 6) on values already worked out —
    // the runtime's mirror of the interpreter's own tool-running,
    // with the same plain words.
    private func runBuiltin(_ name: String, args: [Value], line: Int) throws -> Value {
        switch name {
        case "length":
            switch args[0] {
            case .text(let text): return .number(Double(text.count))
            case .list(let list): return .number(Double(list.items.count))
            case .object(let object): return .number(Double(object.fieldNames.count))
            case .bytes(let bytes): return .number(Double(bytes.data.count))
            default:
                throw NiflaError(line: line, message: "'length' measures some text, a list, an object, or a block of bytes, but it was given \(args[0].described).")
            }

        case "makebytes":
            let count = try wholeCount(args[0], what: "The number of bytes to make", line: line)
            if count < 0 {
                throw NiflaError(line: line, message: "'makebytes' was told to make \(count) bytes, but a count can't be less than 0.")
            }
            if count > 16_777_216 {
                throw NiflaError(line: line, message: "'makebytes' was told to make \(count) bytes, but one block can hold at most 16777216 bytes.")
            }
            return .bytes(NiflaBytes(count: count))

        case "join":
            guard case .list(let list) = args[0] else {
                throw NiflaError(line: line, message: "'join' joins the items of a list into one piece of text, but it was given \(args[0].described) to join. Give it a list first, like: join(words, \" \").")
            }
            guard case .text(let separator) = args[1] else {
                throw NiflaError(line: line, message: "'join' needs some text to join the items with, like \" \" or \", \", but it was given \(args[1].described).")
            }
            return .text(list.items.map { $0.spoken }.joined(separator: separator))

        case "split":
            guard case .text(let text) = args[0] else {
                throw NiflaError(line: line, message: "'split' splits some text into a list of pieces, but it was given \(args[0].described) to split.")
            }
            guard case .text(let separator) = args[1] else {
                throw NiflaError(line: line, message: "'split' needs some text to split by, like \",\", but it was given \(args[1].described).")
            }
            guard !separator.isEmpty else {
                throw NiflaError(line: line, message: "'split' can't split by an empty piece of text — there would be nothing to split on. Give it the text to split by, like: split(\"a,b\", \",\").")
            }
            let pieces = text.components(separatedBy: separator)
            return .list(NiflaList(items: pieces.map { Value.text($0) }))

        case "part":
            guard case .text(let text) = args[0] else {
                throw NiflaError(line: line, message: "'part' takes a part of some text, but it was given \(args[0].described).")
            }
            guard case .number = args[1] else {
                throw NiflaError(line: line, message: "'part' needs a number saying which character to start at — 0 is the first — but it was given \(args[1].described).")
            }
            guard case .number = args[2] else {
                throw NiflaError(line: line, message: "'part' needs a number saying how many characters to take, but it was given \(args[2].described).")
            }
            let start = try wholeCount(args[1], what: "The character to start at", line: line)
            let count = try wholeCount(args[2], what: "The number of characters to take", line: line)
            let chars = Array(text)
            if start < 0 {
                throw NiflaError(line: line, message: "'part' was told to start at character \(start), but the first character is number 0 — a start can't be less than 0.")
            }
            if count < 0 {
                throw NiflaError(line: line, message: "'part' was told to take \(count) characters, but a count can't be less than 0.")
            }
            if start > chars.count {
                if chars.isEmpty {
                    throw NiflaError(line: line, message: "'part' was told to start at character \(start), but the text has no characters yet.")
                }
                throw NiflaError(line: line, message: "'part' was told to start at character \(start), but the text has only \(chars.count) characters, numbered 0 to \(chars.count - 1).")
            }
            if start + count > chars.count {
                throw NiflaError(line: line, message: "'part' was told to take \(count) characters starting at character \(start), but the text has only \(chars.count) characters, numbered 0 to \(chars.count - 1) — that runs past the end.")
            }
            return .text(String(chars[start..<(start + count)]))

        case "find":
            guard case .text(let text) = args[0] else {
                throw NiflaError(line: line, message: "'find' looks for a piece of text inside some text, but it was given \(args[0].described) to look in.")
            }
            guard case .text(let piece) = args[1] else {
                throw NiflaError(line: line, message: "'find' looks for a piece of text inside some text, but it was given \(args[1].described) to look for.")
            }
            let chars = Array(text)
            let wanted = Array(piece)
            if wanted.isEmpty { return .number(0) }
            guard wanted.count <= chars.count else { return .number(-1) }
            for start in 0...(chars.count - wanted.count) {
                if Array(chars[start..<(start + wanted.count)]) == wanted {
                    return .number(Double(start))
                }
            }
            return .number(-1)

        case "append":
            guard case .list(let list) = args[0] else {
                throw NiflaError(line: line, message: "'append' adds a value to the end of a list, but it was given \(args[0].described) to add to.")
            }
            list.items.append(args[1])
            return .list(list)

        case "readfile":
            guard case .text(let path) = args[0] else {
                throw NiflaError(line: line, message: "'readfile' needs the name of a file, as text, but it was given \(args[0].described).")
            }
            do {
                return .text(try String(contentsOfFile: path, encoding: .utf8))
            } catch {
                throw NiflaError(line: line, message: "I couldn't read the file '\(path)'. Check the name and the folder, and try again.")
            }

        case "writefile":
            guard case .text(let path) = args[0] else {
                throw NiflaError(line: line, message: "'writefile' needs the name of a file, as text, but it was given \(args[0].described).")
            }
            guard case .text(let text) = args[1] else {
                throw NiflaError(line: line, message: "'writefile' writes some text to a file, but it was given \(args[1].described) to write.")
            }
            do {
                try text.write(toFile: path, atomically: true, encoding: .utf8)
            } catch {
                throw NiflaError(line: line, message: "I couldn't write the file '\(path)'. Check that the folder is there and the name is right, and try again.")
            }
            return .number(Double(text.count))

        case "arguments":
            return .list(NiflaList(items: programArguments.map { Value.text($0) }))

        case "sayerr":
            let spoken = args[0].spoken
            FileHandle.standardError.write(Data((spoken + "\n").utf8))
            return .number(Double(spoken.count + 1))

        case "exitwith":
            guard case .number(let code) = args[0] else {
                throw NiflaError(line: line, message: "'exitwith' ends the program with a number as its parting word to the system, but it was given \(args[0].described).")
            }
            guard code == code.rounded() && code >= 0 && code <= 255 else {
                throw NiflaError(line: line, message: "'exitwith' needs a whole number from 0 to 255, but it was given \(formatNumber(code)).")
            }
            fflush(stdout)
            exit(Int32(code))

        case "removeat":
            guard case .list(let list) = args[0] else {
                throw NiflaError(line: line, message: "'removeat' takes an item out of a list, but it was given \(args[0].described) to take from.")
            }
            let index = try itemNumber(args[1], line: line)
            if list.items.isEmpty {
                throw NiflaError(line: line, message: "This list has no items yet, so there is no item \(index) to remove.")
            }
            guard index >= 0 && index < list.items.count else {
                throw NiflaError(line: line, message: "This list has \(list.items.count) items, numbered 0 to \(list.items.count - 1), but I was asked to remove item \(index).")
            }
            return list.items.remove(at: index)

        case "insertat":
            guard case .list(let list) = args[0] else {
                throw NiflaError(line: line, message: "'insertat' puts an item into a list, but it was given \(args[0].described) to put into.")
            }
            let index = try itemNumber(args[1], line: line)
            guard index >= 0 && index <= list.items.count else {
                throw NiflaError(line: line, message: "This list has \(list.items.count) items, so a new item can be put in at numbers 0 to \(list.items.count), but I was asked for number \(index).")
            }
            list.items.insert(args[2], at: index)
            return .list(list)

        case "sorted":
            guard case .list(let list) = args[0] else {
                throw NiflaError(line: line, message: "'sorted' sorts a list, but it was given \(args[0].described) to sort.")
            }
            return .list(NiflaList(items: try sortedItems(list.items, line: line)))

        case "fieldnames":
            guard case .object(let object) = args[0] else {
                throw NiflaError(line: line, message: "'fieldnames' lists the field names of an object, as a list of text, but it was given \(args[0].described).")
            }
            return .list(NiflaList(items: object.fieldNames.map { Value.text($0) }))

        case "removefield":
            guard case .object(let object) = args[0] else {
                throw NiflaError(line: line, message: "'removefield' takes a field out of an object, but it was given \(args[0].described) to take from.")
            }
            guard case .text(let fieldName) = args[1] else {
                throw NiflaError(line: line, message: "'removefield' needs the name of a field, as text, but it was given \(args[1].described).")
            }
            guard let removed = object.remove(fieldName) else {
                throw missingFieldError(object: object, field: fieldName, line: line)
            }
            return removed

        default:
            throw NiflaError(line: line, message: "I don't know a tool called '\(name)'.")
        }
    }

    // The items of a list in sorted order (Stone 10), as a new
    // list's items — the runtime's mirror of the interpreter's.
    private func sortedItems(_ items: [Value], line: Int) throws -> [Value] {
        guard let first = items.first else { return [] }
        switch first {
        case .number:
            for (index, item) in items.enumerated() {
                guard case .number = item else {
                    throw NiflaError(line: line, message: "'sorted' needs every item in the list to be the same kind — numbers with numbers, text with text — but item \(index) is \(item.described), while the first item is \(first.described).")
                }
            }
            return items.sorted { a, b in
                guard case .number(let x) = a, case .number(let y) = b else { return false }
                return x < y
            }
        case .text:
            for (index, item) in items.enumerated() {
                guard case .text = item else {
                    throw NiflaError(line: line, message: "'sorted' needs every item in the list to be the same kind — numbers with numbers, text with text — but item \(index) is \(item.described), while the first item is \(first.described).")
                }
            }
            return items.sorted { a, b in
                guard case .text(let x) = a, case .text(let y) = b else { return false }
                return x < y
            }
        default:
            throw NiflaError(line: line, message: "'sorted' can sort a list of numbers or a list of text, but this list starts with \(first.described).")
        }
    }

    // A whole-number check for the counting tools ('part').
    private func wholeCount(_ value: Value, what: String, line: Int) throws -> Int {
        guard case .number(let number) = value else {
            throw NiflaError(line: line, message: "\(what) must be a number, but I was given \(value.described).")
        }
        guard number == number.rounded() && abs(number) < 1e15 else {
            throw NiflaError(line: line, message: "\(what) must be a whole number, but I was given \(formatNumber(number)).")
        }
        return Int(number)
    }

    private func closestFieldName(to name: String, in object: NiflaObject) -> String? {
        var best: (name: String, distance: Int)? = nil
        for candidate in object.fieldNames where candidate != name {
            let distance = editDistance(name, candidate)
            if distance <= 2 && (best == nil || distance < best!.distance) {
                best = (candidate, distance)
            }
        }
        return best?.name
    }

    private func closestName(to name: String, in scope: Scope) -> String? {
        var best: (name: String, distance: Int)? = nil
        for candidate in scope.allNames() where candidate != name {
            let distance = editDistance(name, candidate)
            if distance <= 2 && (best == nil || distance < best!.distance) {
                best = (candidate, distance)
            }
        }
        return best?.name
    }
}
