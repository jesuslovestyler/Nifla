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
}

enum Value {
    case number(Double)
    case text(String)
    case boolean(Bool)
    case object(NiflaObject)

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

    // Runs one call, in the interpreter's own order: the function
    // must exist, then the handed values are worked out, then their
    // number is checked, then the depth guard, then the body runs
    // in a fresh scope inside the function's home.
    private func callFunction(name: String, argExprs: [() throws -> Value], line: Int) throws -> Value? {
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
        for candidate in functions.keys where candidate != name {
            let distance = editDistance(name, candidate)
            if distance <= 2 && (best == nil || distance < best!.distance) {
                best = (candidate, distance)
            }
        }
        return best?.name
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
