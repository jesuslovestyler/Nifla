// Nifla — Stone 1 interpreter: the interpreter.
//
// Walks the parser's tree and runs it: values, variables in nested
// scopes (one per block), and the running of statements. All problems
// are reported as plain-words NiflaErrors with a line number.

enum Value {
    case number(Double)
    case text(String)
    case boolean(Bool)

    // How the value is shown by `say`.
    var spoken: String {
        switch self {
        case .number(let value): return formatNumber(value)
        case .text(let value): return value
        case .boolean(let value): return value ? "true" : "false"
        }
    }

    // How the value is described inside an error message.
    var described: String {
        switch self {
        case .number(let value): return "the number \(formatNumber(value))"
        case .text(let value): return "the text \"\(value)\""
        case .boolean(let value): return value ? "true" : "false"
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

final class Interpreter {
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
        }
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
