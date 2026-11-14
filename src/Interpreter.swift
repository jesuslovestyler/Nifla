// Nifla — Stone 1 interpreter: the interpreter.
//
// Walks the parser's tree and runs it: values, variables in nested
// scopes (one per block), and the running of statements. All problems
// are reported as plain-words NiflaErrors with a line number.

// An object (Stone 4): named fields, kept in the order they were
// first written. It is a class on purpose — objects are shared by
// reference, the way JavaScript's are. Two variables that hold the
// same object see each other's changes to its fields.
final class NiflaObject {
    private(set) var fieldNames: [String] = []
    private var values: [String: Value] = [:]

    func value(for name: String) -> Value? {
        values[name]
    }

    // Sets a field: an existing field keeps its place in the order;
    // a new one is added at the end.
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

    // The one renderer behind `spoken`. An object is shown as a
    // readable listing of its fields — { name: "Tyler", years: 29 } —
    // with text values in quotes inside a listing, so they can't be
    // mistaken for numbers, and nested objects listed the same way.
    // `seen` holds the objects already being listed on the way here,
    // so an object that (through its fields) contains itself stops
    // at "..." instead of listing forever.
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

// One scope of variables. Blocks get their own scope, linked to the
// scope around them; a variable made inside a block stays inside it.
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

    func isDeclaredAnywhere(_ name: String) -> Bool {
        lookup(name) != nil
    }

    func declare(_ name: String, _ value: Value) {
        values[name] = value
    }

    // Sets the variable in whichever scope made it. Returns false when
    // no scope knows the name.
    func assign(_ name: String, _ value: Value) -> Bool {
        if values[name] != nil {
            values[name] = value
            return true
        }
        return parent?.assign(name, value) ?? false
    }

    // Every name visible from here, for "did you mean" suggestions.
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

// A function made with 'make' (Stone 3): the names it takes, the
// statements it runs, and the scope it was made in — its home. The
// body runs in a fresh scope inside that home, so a function sees the
// variables around its making, the way a block does, while its own
// names stay inside it.
struct FunctionDef {
    let params: [String]
    let body: [Stmt]
    let home: Scope
}

// How a 'give' line hands its value back: it is thrown like an error
// and caught by the call that is running the function. It never
// reaches the person writing Nifla.
private struct ReturnSignal: Error {
    let value: Value
}

final class Interpreter {
    // The runaway guard (Stone 2): a kindness limit on the total number
    // of loop passes in one run, across every loop in the program. A
    // loop that would spin forever is stopped with a plain-words error
    // instead of hanging.
    private var loopPasses = 0
    private let loopPassLimit = 1_000_000

    // The functions this run has made, by name (Stone 3).
    private var functions: [String: FunctionDef] = [:]

    // The call-depth guard (Stone 3): how many calls are running at
    // once, one inside another. A function that calls itself without a
    // way to stop is caught by this limit and stopped with a
    // plain-words error instead of crashing.
    private var callDepth = 0
    private let callDepthLimit = 500

    private func tickLoop(line: Int) throws {
        loopPasses += 1
        if loopPasses > loopPassLimit {
            throw NiflaError(line: line, message: "This loop ran more than a million times and was stopped — it may never end. Check the condition, and make sure something inside the loop changes each time around, so it can finish.")
        }
    }

    func run(_ program: [Stmt]) throws {
        let top = Scope()
        for statement in program {
            try execute(statement, in: top)
        }
    }

    private func execute(_ statement: Stmt, in scope: Scope) throws {
        switch statement {
        case .declare(let name, let valueExpr, let line):
            if scope.isDeclaredHere(name) {
                throw NiflaError(line: line, message: "There is already a variable called '\(name)' in this block. To change what it holds, write: \(name) = ...")
            }
            scope.declare(name, try evaluate(valueExpr, in: scope))

        case .assign(let name, let valueExpr, let line):
            let value = try evaluate(valueExpr, in: scope)
            if !scope.assign(name, value) {
                throw NiflaError(line: line, message: "I can't set '\(name)', because no variable called '\(name)' has been made yet. Make one first with: let \(name) = ...")
            }

        case .assignField(let target, let valueExpr, let line):
            // The target is a chain of field steps; every step but
            // the last is read, to reach the object whose field is
            // being set, and the last step names that field. Setting
            // a field that isn't there yet adds it.
            guard case .field(let baseExpr, let fieldName, _) = target else {
                throw NiflaError(line: line, message: "I can only set a field on an object, like: person.years = 30.")
            }
            let base = try evaluate(baseExpr, in: scope)
            guard case .object(let object) = base else {
                throw NiflaError(line: line, message: "I can't set the field '\(fieldName)' on \(base.described), because only an object has fields. Make an object first, like: let person = { name: \"Tyler\" } — then person.\(fieldName) = ... works.")
            }
            object.set(fieldName, try evaluate(valueExpr, in: scope))

        case .say(let valueExpr, _):
            let value = try evaluate(valueExpr, in: scope)
            print(value.spoken)

        case .ifElse(let condition, let thenBlock, let elseBlock, let line):
            let value = try evaluate(condition, in: scope)
            guard case .boolean(let flag) = value else {
                throw NiflaError(line: line, message: "'if' needs a true or false value to decide with, but here it was given \(value.described). Try a comparison, like: if years > 12 { ... }")
            }
            let block = flag ? thenBlock : (elseBlock ?? [])
            let child = Scope(parent: scope)
            for inner in block {
                try execute(inner, in: child)
            }

        case .whileLoop(let condition, let body, let line):
            // The condition is checked before every pass. Each pass
            // runs the body in a fresh block scope, the same way 'if'
            // does: 'let' inside is new each pass, while setting a
            // variable reaches the one outside — that is how counting
            // works.
            while true {
                let value = try evaluate(condition, in: scope)
                guard case .boolean(let flag) = value else {
                    throw NiflaError(line: line, message: "'while' needs a true or false value to decide with, but here it was given \(value.described). Try a comparison, like: while years < 40 { ... }")
                }
                if !flag { break }
                try tickLoop(line: line)
                let child = Scope(parent: scope)
                for inner in body {
                    try execute(inner, in: child)
                }
            }

        case .repeatLoop(let countExpr, let body, let line):
            // The count is worked out once, before the loop starts,
            // and must be a whole number, zero or more.
            let value = try evaluate(countExpr, in: scope)
            guard case .number(let count) = value else {
                throw NiflaError(line: line, message: "'repeat' needs a number saying how many times to run, but here it was given \(value.described). Write it like: repeat 3 { ... }")
            }
            if count < 0 {
                throw NiflaError(line: line, message: "'repeat' was told to run \(formatNumber(count)) times, but a count can't be negative — a loop can't run less than zero times. Use zero or more, like: repeat 3 { ... }")
            }
            if count != count.rounded() {
                throw NiflaError(line: line, message: "'repeat' was told to run \(formatNumber(count)) times, but a loop can only run a whole number of times. Use a whole number instead, like \(formatNumber(count.rounded(.down))) or \(formatNumber(count.rounded(.up))).")
            }
            var done = 0.0
            while done < count {
                try tickLoop(line: line)
                let child = Scope(parent: scope)
                for inner in body {
                    try execute(inner, in: child)
                }
                done += 1
            }

        case .define(let name, let params, let body, let line):
            // Making a function is a line like any other: it runs when
            // the program reaches it, so a function is ready to call
            // from that line on.
            if functions[name] != nil {
                throw NiflaError(line: line, message: "There is already a function called '\(name)'. Each function needs its own name — rename this one, or take out the earlier 'make \(name)'.")
            }
            functions[name] = FunctionDef(params: params, body: body, home: scope)

        case .give(let valueExpr, let line):
            guard callDepth > 0 else {
                throw NiflaError(line: line, message: "'give' hands a value back from a function to whoever called it, but this line is not inside a function. To show a value here, use 'say' instead.")
            }
            throw ReturnSignal(value: try evaluate(valueExpr, in: scope))

        case .doCall(let name, let args, let line):
            // A call on its own line: run it for what it does. Any
            // value it gives back is simply not used.
            _ = try callFunction(name: name, argExprs: args, line: line, in: scope)
        }
    }

    // Runs one call: checks the function exists and was given the
    // right number of values, then runs its body in a fresh scope
    // inside its home, with the parameters declared there. Returns
    // the value the function gave back, or nil when it finished
    // without a 'give'.
    private func callFunction(name: String, argExprs: [Expr], line: Int, in scope: Scope) throws -> Value? {
        guard let def = functions[name] else {
            var message = "I don't know a function called '\(name)' yet. You can make one with: make \(name)(...) { ... }"
            if let suggestion = closestFunctionName(to: name) {
                message += " Did you mean '\(suggestion)'?"
            }
            throw NiflaError(line: line, message: message)
        }
        let args = try argExprs.map { try evaluate($0, in: scope) }
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
            for inner in def.body {
                try execute(inner, in: callScope)
            }
        } catch let signal as ReturnSignal {
            return signal.value
        }
        return nil
    }

    // "no values", "1 value (name)", "2 values (a, b)" — for the
    // wrong-number-of-values error.
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

    private func evaluate(_ expr: Expr, in scope: Scope) throws -> Value {
        switch expr {
        case .number(let value, _):
            return .number(value)
        case .text(let value, _):
            return .text(value)
        case .boolean(let value, _):
            return .boolean(value)

        case .variable(let name, let line):
            if let value = scope.lookup(name) {
                return value
            }
            var message = "I don't know a variable called '\(name)' yet. You can make one with: let \(name) = ..."
            if let suggestion = closestName(to: name, in: scope) {
                message += " Did you mean '\(suggestion)'?"
            }
            throw NiflaError(line: line, message: message)

        case .call(let name, let args, let line):
            guard let value = try callFunction(name: name, argExprs: args, line: line, in: scope) else {
                throw NiflaError(line: line, message: "The function '\(name)' finished without giving a value back, so there is nothing to use here. Add a 'give' line inside '\(name)', or call it on its own line instead.")
            }
            return value

        case .object(let fields, _):
            let object = NiflaObject()
            for field in fields {
                object.set(field.name, try evaluate(field.value, in: scope))
            }
            return .object(object)

        case .field(let baseExpr, let name, let line):
            let base = try evaluate(baseExpr, in: scope)
            guard case .object(let object) = base else {
                throw NiflaError(line: line, message: "I can't read the field '\(name)' of \(base.described), because only an object has fields. Make an object first, like: let person = { name: \"Tyler\" } — then person.name works.")
            }
            guard let value = object.value(for: name) else {
                throw missingFieldError(object: object, field: name, line: line)
            }
            return value

        case .negate(let inner, let line):
            let value = try evaluate(inner, in: scope)
            guard case .number(let number) = value else {
                throw NiflaError(line: line, message: "I can only put a minus sign in front of a number, but here it was in front of \(value.described).")
            }
            return .number(-number)

        case .binary(let leftExpr, let op, let rightExpr, let line):
            let left = try evaluate(leftExpr, in: scope)
            let right = try evaluate(rightExpr, in: scope)
            return try apply(op, left, right, line: line)
        }
    }

    // Reading a field an object doesn't have: say which fields it
    // does have, and suggest a close one when there is one.
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

    private func apply(_ op: String, _ left: Value, _ right: Value, line: Int) throws -> Value {
        switch op {
        case "+":
            // Text joins with anything, the way JavaScript joins strings.
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
            case (.object(let a), .object(let b)): equal = a === b  // the very same object, not just alike
            default: equal = false  // different kinds are never equal
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
}
