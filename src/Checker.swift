// Nifla — Stone 5: the checker.
//
// A quiet pass over the parsed program that runs BEFORE anything is
// run or compiled — the Swift-like safety. It walks the program in
// the order it would run, keeping track of what it can prove about
// each variable's kind (number, text, true/false, object) from
// literals and from 'let' lines whose value's kind is clear.
//
// It speaks only when it is sure:
//   - a '+' , '-', '*', '/', '<', '<=', '>' or '>=' whose two sides'
//     kinds are both known and can never work together
//   - a call to a function that is never made anywhere in the program
//   - a call whose number of values doesn't match the function's
//   - a variable used (or set) that no 'let' has made
//
// Where a kind can't be proven — a value handed into a function, a
// field read out of an object, a function's answer — the checker
// stays silent, and the interpreter's own checks (which run as the
// program runs, with the same plain words) remain the guard. For the
// three name-and-count mistakes, the checker uses the interpreter's
// exact words, so a program it stops reads exactly as it would have
// read when the interpreter stopped it.
//
// One more honesty: because a function can set variables outside
// itself, the checker forgets every kind it thought it knew whenever
// a function is called. Better silent than wrong.

// What the checker can prove about a value's kind. 'unknown' means
// "can't be proven from here" — the checker stays silent about it.
enum StaticKind {
    case number
    case text
    case boolean
    case object
    case list
    case bytes
    case unknown

    // How the kind is named in a plain-words message.
    var phrase: String {
        switch self {
        case .number: return "a number"
        case .text: return "some text"
        case .boolean: return "a true/false value"
        case .object: return "an object"
        case .list: return "a list"
        case .bytes: return "a block of bytes"
        case .unknown: return "a value"
        }
    }
}

// The checker's rules for the built-in tools (Stone 6): the kind
// a call to the tool provably gives back, and — for each value the
// tool takes — the kinds that value may have and how the need is
// phrased when a known kind can never work. A nil kind set means
// any kind will do. The checker speaks about a tool only when a
// handed value's kind is proven and can never work; the tools'
// other rules (ranges, files, and the like) belong to the run.
private struct BuiltinRule {
    let result: StaticKind
    let needs: [(kinds: Set<StaticKind>?, need: String)]
}

private let builtinRules: [String: BuiltinRule] = [
    "length": BuiltinRule(result: .number, needs: [([.text, .list, .object, .bytes], "some text, a list, an object, or a block of bytes to measure")]),
    "join": BuiltinRule(result: .text, needs: [([.list], "a list to join"), ([.text], "some text to join the items with")]),
    "split": BuiltinRule(result: .list, needs: [([.text], "some text to split"), ([.text], "some text to split by")]),
    "part": BuiltinRule(result: .text, needs: [([.text], "some text to take a part of"), ([.number], "a number saying which character to start at"), ([.number], "a number saying how many characters to take")]),
    "find": BuiltinRule(result: .number, needs: [([.text], "some text to look in"), ([.text], "some text to look for")]),
    "append": BuiltinRule(result: .list, needs: [([.list], "a list to add to"), (nil, "")]),
    "readfile": BuiltinRule(result: .text, needs: [([.text], "the name of a file, as text")]),
    "writefile": BuiltinRule(result: .number, needs: [([.text], "the name of a file, as text"), ([.text], "some text to write")]),
    "arguments": BuiltinRule(result: .list, needs: []),
    "makebytes": BuiltinRule(result: .bytes, needs: [([.number], "a number saying how many bytes to make")]),
    "sayerr": BuiltinRule(result: .number, needs: [(nil, "")]),
    "exitwith": BuiltinRule(result: .unknown, needs: [([.number], "a whole number from 0 to 255 to end with")]),
    "removeat": BuiltinRule(result: .unknown, needs: [([.list], "a list to take an item from"), ([.number], "a number saying which item to take out")]),
    "insertat": BuiltinRule(result: .list, needs: [([.list], "a list to put an item into"), ([.number], "a number saying where to put the new item"), (nil, "")]),
    "sorted": BuiltinRule(result: .list, needs: [([.list], "a list to sort")]),
    "fieldnames": BuiltinRule(result: .list, needs: [([.object], "an object to list the field names of")]),
    "removefield": BuiltinRule(result: .unknown, needs: [([.object], "an object to take a field from"), ([.text], "the name of a field, as text")]),
]

// The checker's picture of the scopes: a stack of blocks, each
// holding the names made in it and the kind proven for each. It is a
// value on purpose — a copy is a snapshot, so the two sides of an
// 'if' (or a loop body, which may run zero times) can each be
// checked and then merged: a name whose kind differs between the
// ways things could go becomes unknown.
struct StaticEnv {
    private(set) var scopes: [[String: StaticKind]] = [[:]]

    func lookup(_ name: String) -> StaticKind? {
        for scope in scopes.reversed() {
            if let kind = scope[name] { return kind }
        }
        return nil
    }

    func isDeclaredHere(_ name: String) -> Bool {
        scopes.last?[name] != nil
    }

    mutating func declare(_ name: String, _ kind: StaticKind) {
        scopes[scopes.count - 1][name] = kind
    }

    // Sets the kind in whichever block made the name. Returns false
    // when no block knows the name.
    mutating func assign(_ name: String, _ kind: StaticKind) -> Bool {
        for index in scopes.indices.reversed() {
            if scopes[index][name] != nil {
                scopes[index][name] = kind
                return true
            }
        }
        return false
    }

    func allNames() -> [String] {
        var names: [String] = []
        for scope in scopes {
            names += scope.keys
        }
        return names
    }

    mutating func pushScope() {
        scopes.append([:])
    }

    mutating func popScope() {
        scopes.removeLast()
    }

    // After a function call, a function may have set any variable it
    // can reach, to anything. Forget every proven kind; keep the
    // names (they were still made).
    mutating func forgetKinds() {
        for index in scopes.indices {
            for name in scopes[index].keys {
                scopes[index][name] = .unknown
            }
        }
    }

    // Merge two ways the program could have gone (the two sides of
    // an 'if', or a loop body against the state before it): a name
    // keeps its kind only when both ways agree on it.
    static func merged(_ a: StaticEnv, _ b: StaticEnv) -> StaticEnv {
        var result = a
        let count = min(a.scopes.count, b.scopes.count)
        for index in 0..<count {
            var scope: [String: StaticKind] = [:]
            let names = Set(a.scopes[index].keys).union(b.scopes[index].keys)
            for name in names {
                let kindA = a.scopes[index][name]
                let kindB = b.scopes[index][name]
                if let kindA, let kindB {
                    scope[name] = kindA == kindB ? kindA : .unknown
                } else if let kind = kindA ?? kindB {
                    scope[name] = kind
                }
            }
            result.scopes[index] = scope
        }
        return result
    }
}

final class Checker {
    // Every function made anywhere in the program, by name, with the
    // names of the values it takes. Collected before checking, so a
    // function can call itself (and a function made later can be
    // called from inside an earlier one's body, as the interpreter
    // allows when the call happens after the making). When a name is
    // made twice, the first making is the one recorded; the
    // interpreter stops a second making when it runs, as before.
    private var functions: [String: [String]] = [:]

    // Stone 11: when the program is being compiled for bare
    // metal, the floor desk differs — it carries numbers and
    // one piece of text (on its memory side), and a bare floor
    // block gives back only a number. checkFloor follows the
    // target it is checking for; every other rule is the same.
    private let forBareMetal: Bool
    // Stone 17: when the bare program is a guest, the guest
    // door's rules apply (see checkBareToolCall).
    private let forGuest: Bool

    init(program: [Stmt], forBareMetal: Bool = false, forGuest: Bool = false) {
        self.forBareMetal = forBareMetal
        self.forGuest = forGuest
        collectFunctions(program)
    }

    func check(_ program: [Stmt]) throws {
        var env = StaticEnv()
        try checkBlock(program, env: &env, outerNames: [])
    }

    private func collectFunctions(_ statements: [Stmt]) {
        for statement in statements {
            switch statement {
            case .define(let name, let params, let body, _):
                if functions[name] == nil { functions[name] = params }
                collectFunctions(body)
            case .attempt(let body, let recovery, _):
                collectFunctions(body)
                collectFunctions(recovery)
            case .ifElse(_, let thenBlock, let elseBlock, _):
                collectFunctions(thenBlock)
                if let elseBlock { collectFunctions(elseBlock) }
            case .whileLoop(_, let body, _), .repeatLoop(_, let body, _), .forEach(_, _, let body, _):
                collectFunctions(body)
            default:
                break
            }
        }
    }

    // The names 'let' makes directly in a block. A function made in
    // this block can see names made anywhere in it by the time it is
    // called, so these join the set of names a function body may use
    // without the checker calling them unmade.
    private func declaredNames(in statements: [Stmt]) -> Set<String> {
        var names = Set<String>()
        for statement in statements {
            if case .declare(let name, _, _) = statement {
                names.insert(name)
            }
        }
        return names
    }

    // Checks a list of statements in one block scope. `outerNames`
    // accumulates the names made in the blocks around this one, for
    // the sake of function bodies (see checkDefine).
    private func checkBlock(_ statements: [Stmt], env: inout StaticEnv, outerNames: Set<String>) throws {
        let outer = outerNames.union(declaredNames(in: statements))
        for statement in statements {
            try checkStatement(statement, env: &env, outerNames: outer)
        }
    }

    // Checks a block that runs as a child scope of the current one
    // (an 'if' side or a loop body), merging what it may have
    // changed on the way out.
    private func checkChildBlock(_ statements: [Stmt], env: inout StaticEnv, outerNames: Set<String>, mergeWithBefore: Bool) throws {
        let before = env
        env.pushScope()
        try checkBlock(statements, env: &env, outerNames: outerNames)
        env.popScope()
        if mergeWithBefore {
            env = StaticEnv.merged(before, env)
        }
    }

    private func checkStatement(_ statement: Stmt, env: inout StaticEnv, outerNames: Set<String>) throws {
        switch statement {
        case .declare(let name, let valueExpr, _):
            let kind = try checkExpr(valueExpr, env: &env, outerNames: outerNames)
            env.declare(name, kind)

        case .assign(let name, let valueExpr, let line):
            // The interpreter works the value out first, then looks
            // for the variable — so the checker reads in that order.
            let kind = try checkExpr(valueExpr, env: &env, outerNames: outerNames)
            if env.lookup(name) == nil {
                throw NiflaError(line: line, message: "I can't set '\(name)', because no variable called '\(name)' has been made yet. Make one first with: let \(name) = ...")
            }
            _ = env.assign(name, kind)

        case .assignTarget(let target, let valueExpr, _):
            _ = try checkExpr(target, env: &env, outerNames: outerNames)
            _ = try checkExpr(valueExpr, env: &env, outerNames: outerNames)

        case .say(let valueExpr, _):
            _ = try checkExpr(valueExpr, env: &env, outerNames: outerNames)

        case .ifElse(let condition, let thenBlock, let elseBlock, _):
            _ = try checkExpr(condition, env: &env, outerNames: outerNames)
            let before = env
            try checkChildBlock(thenBlock, env: &env, outerNames: outerNames, mergeWithBefore: false)
            let afterThen = env
            env = before
            if let elseBlock {
                try checkChildBlock(elseBlock, env: &env, outerNames: outerNames, mergeWithBefore: false)
            }
            env = StaticEnv.merged(afterThen, env)

        case .whileLoop(let condition, let body, _):
            _ = try checkExpr(condition, env: &env, outerNames: outerNames)
            try checkChildBlock(body, env: &env, outerNames: outerNames, mergeWithBefore: true)

        case .repeatLoop(let count, let body, _):
            _ = try checkExpr(count, env: &env, outerNames: outerNames)
            try checkChildBlock(body, env: &env, outerNames: outerNames, mergeWithBefore: true)

        case .forEach(let name, let over, let body, _):
            _ = try checkExpr(over, env: &env, outerNames: outerNames)
            let before = env
            env.pushScope()
            env.declare(name, .unknown)
            try checkBlock(body, env: &env, outerNames: outerNames)
            env.popScope()
            env = StaticEnv.merged(before, env)

        case .define(let name, let params, let body, _):
            try checkDefine(name: name, params: params, body: body, env: env, outerNames: outerNames)

        case .give(let valueExpr, _):
            _ = try checkExpr(valueExpr, env: &env, outerNames: outerNames)

        case .attempt(let body, let recovery, _):
            // Either block may be the one that runs to the end —
            // the attempt may fail partway through — so both are
            // checked from the state before, and what follows sees
            // the merge of the two ways it could have gone. The
            // recovery block also holds 'problem', some text.
            let before = env
            try checkChildBlock(body, env: &env, outerNames: outerNames, mergeWithBefore: false)
            let afterBody = env
            env = before
            env.pushScope()
            env.declare("problem", .text)
            try checkBlock(recovery, env: &env, outerNames: outerNames)
            env.popScope()
            env = StaticEnv.merged(afterBody, env)

        case .doCall(let name, let args, let line):
            try checkCall(name: name, args: args, line: line, env: &env, outerNames: outerNames)

        case .doExpr(let expr, _):
            _ = try checkExpr(expr, env: &env, outerNames: outerNames)
        }
    }

    // A function body is checked where the function is made, in a
    // fresh block inside the scopes around the making, with the
    // values it takes declared there (their kinds unknown — they
    // depend on whoever calls). Names the body uses that aren't in
    // that picture are only called unmade when no 'let' anywhere
    // around the making makes them either — a function is called
    // later, and by then a later 'let' in an enclosing block has
    // run. What the body may have changed is not carried back: a
    // body may never run at all.
    private func checkDefine(name: String, params: [String], body: [Stmt], env: StaticEnv, outerNames: Set<String>) throws {
        var bodyEnv = env
        bodyEnv.pushScope()
        for param in params {
            bodyEnv.declare(param, .unknown)
        }
        let bodyOuter = outerNames.union(declaredNames(in: body))
        for statement in body {
            try checkStatementInFunction(statement, env: &bodyEnv, outerNames: bodyOuter)
        }
    }

    // Statements inside a function body are checked like any others,
    // except that a variable name found nowhere is forgiven when a
    // 'let' for it exists in a block around the function's making
    // (it will have run by the time the function is called). Nested
    // function makings keep the same forgiveness.
    private func checkStatementInFunction(_ statement: Stmt, env: inout StaticEnv, outerNames: Set<String>) throws {
        switch statement {
        case .define(let name, let params, let body, _):
            try checkDefine(name: name, params: params, body: body, env: env, outerNames: outerNames)
        default:
            try checkStatementWithForgiveness(statement, env: &env, outerNames: outerNames)
        }
    }

    // A wrapper used only inside function bodies: it runs the
    // ordinary checks, but an "unmade variable" error for a name in
    // `outerNames` is forgiven (see checkDefine). Implemented by
    // catching that one error when the name is in the forgiven set.
    private func checkStatementWithForgiveness(_ statement: Stmt, env: inout StaticEnv, outerNames: Set<String>) throws {
        // Blocks inside a function body need the same forgiveness, so
        // this recurses through the statement shapes rather than
        // delegating wholesale.
        switch statement {
        case .declare(let name, let valueExpr, _):
            let kind = try checkExprForgiving(valueExpr, env: &env, outerNames: outerNames)
            env.declare(name, kind)

        case .assign(let name, let valueExpr, let line):
            let kind = try checkExprForgiving(valueExpr, env: &env, outerNames: outerNames)
            if env.lookup(name) == nil && !outerNames.contains(name) {
                throw NiflaError(line: line, message: "I can't set '\(name)', because no variable called '\(name)' has been made yet. Make one first with: let \(name) = ...")
            }
            _ = env.assign(name, kind)

        case .assignTarget(let target, let valueExpr, _):
            _ = try checkExprForgiving(target, env: &env, outerNames: outerNames)
            _ = try checkExprForgiving(valueExpr, env: &env, outerNames: outerNames)

        case .say(let valueExpr, _):
            _ = try checkExprForgiving(valueExpr, env: &env, outerNames: outerNames)

        case .ifElse(let condition, let thenBlock, let elseBlock, _):
            _ = try checkExprForgiving(condition, env: &env, outerNames: outerNames)
            let before = env
            try checkChildBlockInFunction(thenBlock, env: &env, outerNames: outerNames)
            let afterThen = env
            env = before
            if let elseBlock {
                try checkChildBlockInFunction(elseBlock, env: &env, outerNames: outerNames)
            }
            env = StaticEnv.merged(afterThen, env)

        case .whileLoop(let condition, let body, _):
            _ = try checkExprForgiving(condition, env: &env, outerNames: outerNames)
            let before = env
            try checkChildBlockInFunction(body, env: &env, outerNames: outerNames)
            env = StaticEnv.merged(before, env)

        case .repeatLoop(let count, let body, _):
            _ = try checkExprForgiving(count, env: &env, outerNames: outerNames)
            let before = env
            try checkChildBlockInFunction(body, env: &env, outerNames: outerNames)
            env = StaticEnv.merged(before, env)

        case .forEach(let name, let over, let body, _):
            _ = try checkExprForgiving(over, env: &env, outerNames: outerNames)
            let before = env
            env.pushScope()
            env.declare(name, .unknown)
            let outer = outerNames.union(declaredNames(in: body))
            for inner in body {
                try checkStatementInFunction(inner, env: &env, outerNames: outer)
            }
            env.popScope()
            env = StaticEnv.merged(before, env)

        case .define(let name, let params, let body, _):
            try checkDefine(name: name, params: params, body: body, env: env, outerNames: outerNames)

        case .give(let valueExpr, _):
            _ = try checkExprForgiving(valueExpr, env: &env, outerNames: outerNames)

        case .attempt(let body, let recovery, _):
            let before = env
            env.pushScope()
            let bodyOuter = outerNames.union(declaredNames(in: body))
            for inner in body {
                try checkStatementInFunction(inner, env: &env, outerNames: bodyOuter)
            }
            env.popScope()
            let afterBody = env
            env = before
            env.pushScope()
            env.declare("problem", .text)
            let recoveryOuter = outerNames.union(declaredNames(in: recovery))
            for inner in recovery {
                try checkStatementInFunction(inner, env: &env, outerNames: recoveryOuter)
            }
            env.popScope()
            env = StaticEnv.merged(afterBody, env)

        case .doCall(let name, let args, let line):
            try checkCallForgiving(name: name, args: args, line: line, env: &env, outerNames: outerNames)

        case .doExpr(let expr, _):
            _ = try checkExprForgiving(expr, env: &env, outerNames: outerNames)
        }
    }

    private func checkChildBlockInFunction(_ statements: [Stmt], env: inout StaticEnv, outerNames: Set<String>) throws {
        env.pushScope()
        let outer = outerNames.union(declaredNames(in: statements))
        for statement in statements {
            try checkStatementInFunction(statement, env: &env, outerNames: outer)
        }
        env.popScope()
    }

    // Checks a call to a built-in tool: the number of values
    // (refused in the run's own words, as with made functions), and
    // each handed value whose kind is proven and can never work
    // for the tool. Returns the kind the tool gives back.
    @discardableResult
    private func checkBuiltinCall(name: String, args: [Expr], line: Int, env: inout StaticEnv, outerNames: Set<String>, forgiving: Bool) throws -> StaticKind {
        let def = builtinTools[name]!
        let rule = builtinRules[name]!
        var kinds: [StaticKind] = []
        for arg in args {
            if forgiving {
                kinds.append(try checkExprForgiving(arg, env: &env, outerNames: outerNames))
            } else {
                kinds.append(try checkExpr(arg, env: &env, outerNames: outerNames))
            }
        }
        guard args.count == def.params.count else {
            throw NiflaError(line: line, message: builtinCountMessage(name: name, def: def, given: args.count))
        }
        for (index, kind) in kinds.enumerated() where kind != .unknown {
            let need = rule.needs[index]
            if let allowed = need.kinds, !allowed.contains(kind) {
                throw NiflaError(line: line, message: "'\(name)' needs \(need.need), but it was given \(kind.phrase). I caught this before the program ran, so nothing ran.")
            }
        }
        return rule.result
    }

    // Stone 12: the bare-only tools (the timer and the keyboard
    // doors, and what later bare stones add). They exist only
    // when the program is being checked for bare metal; the
    // table itself lives with the bare target (BareCompiler
    // .swift). When the name is one of them, the handed values
    // are checked and their number verified, and the kind the
    // tool gives back — always a number — is returned. When it
    // isn't (or this check isn't for bare metal), returns nil
    // and the ordinary rules apply: on hosted targets these
    // names are simply functions the checker doesn't know.
    private func checkBareToolCall(name: String, args: [Expr], line: Int, env: inout StaticEnv, outerNames: Set<String>, forgiving: Bool) throws -> StaticKind? {
        guard forBareMetal else { return nil }
        // Stone 17: the guest door. Each side has its own
        // tools, and the machine's own tools stay with the
        // host; crossing any of those lines is refused here,
        // in plain words, before anything is built.
        var arity: Int? = nil
        if forGuest {
            if bareOnlyTools[name] != nil {
                throw NiflaError(line: line, message: "'\(name)' belongs to the host — a guest does not own the machine's timer, keyboard, memory map, or disk; the host keeps those. A guest's world is the screen, its own heap, and the desk the host hands it (guestvalue and guestgive). I caught this before the program ran, so nothing ran.")
            }
            if guestDoorTools[name] != nil {
                throw NiflaError(line: line, message: "'\(name)' is the host's door — a guest cannot call a guest. Only the host program, the one that was booted, opens the door. I caught this before the program ran, so nothing ran.")
            }
            arity = guestDeskTools[name]
        } else if guestDeskTools[name] != nil {
            throw NiflaError(line: line, message: "'\(name)' is a guest's tool — it speaks through the desk a host hands a guest, and this program is not being built as a guest. Build it with 'niflac --bare --guest' to make it a guest, or take the call out. I caught this before the program ran, so nothing ran.")
        } else if let doorArity = guestDoorTools[name] {
            arity = doorArity
        }
        if arity == nil {
            arity = bareOnlyTools[name]
        }
        guard let arity else { return nil }
        for arg in args {
            if forgiving {
                _ = try checkExprForgiving(arg, env: &env, outerNames: outerNames)
            } else {
                _ = try checkExpr(arg, env: &env, outerNames: outerNames)
            }
        }
        guard args.count == arity else {
            if arity == 0 {
                throw NiflaError(line: line, message: "'\(name)' takes no values, but it was given \(args.count). Call it with nothing between the parentheses: \(name)(). I caught this before the program ran, so nothing ran.")
            }
            throw NiflaError(line: line, message: "'\(name)' takes \(arity) values, but it was given \(args.count). I caught this before the program ran, so nothing ran.")
        }
        return .number
    }

    private func checkCall(name: String, args: [Expr], line: Int, env: inout StaticEnv, outerNames: Set<String>) throws {
        if builtinTools[name] != nil {
            _ = try checkBuiltinCall(name: name, args: args, line: line, env: &env, outerNames: outerNames, forgiving: false)
            return
        }
        if try checkBareToolCall(name: name, args: args, line: line, env: &env, outerNames: outerNames, forgiving: false) != nil {
            return
        }
        guard let params = functions[name] else {
            var message = "I don't know a function called '\(name)' yet. You can make one with: make \(name)(...) { ... }"
            if let suggestion = closestFunctionName(to: name) {
                message += " Did you mean '\(suggestion)'?"
            }
            throw NiflaError(line: line, message: message)
        }
        for arg in args {
            _ = try checkExpr(arg, env: &env, outerNames: outerNames)
        }
        guard args.count == params.count else {
            throw NiflaError(line: line, message: "The function '\(name)' takes \(takesText(params)), but it was given \(args.count). Make the call match how the function was made: \(name)(\(params.joined(separator: ", "))).")
        }
        env.forgetKinds()
    }

    private func checkCallForgiving(name: String, args: [Expr], line: Int, env: inout StaticEnv, outerNames: Set<String>) throws {
        if builtinTools[name] != nil {
            _ = try checkBuiltinCall(name: name, args: args, line: line, env: &env, outerNames: outerNames, forgiving: true)
            return
        }
        if try checkBareToolCall(name: name, args: args, line: line, env: &env, outerNames: outerNames, forgiving: true) != nil {
            return
        }
        guard let params = functions[name] else {
            var message = "I don't know a function called '\(name)' yet. You can make one with: make \(name)(...) { ... }"
            if let suggestion = closestFunctionName(to: name) {
                message += " Did you mean '\(suggestion)'?"
            }
            throw NiflaError(line: line, message: message)
        }
        for arg in args {
            _ = try checkExprForgiving(arg, env: &env, outerNames: outerNames)
        }
        guard args.count == params.count else {
            throw NiflaError(line: line, message: "The function '\(name)' takes \(takesText(params)), but it was given \(args.count). Make the call match how the function was made: \(name)(\(params.joined(separator: ", "))).")
        }
        env.forgetKinds()
    }

    // Reads an expression and returns the kind it provably has.
    private func checkExpr(_ expr: Expr, env: inout StaticEnv, outerNames: Set<String>) throws -> StaticKind {
        switch expr {
        case .number:
            return .number
        case .text:
            return .text
        case .boolean:
            return .boolean

        case .variable(let name, let line):
            if let kind = env.lookup(name) {
                return kind
            }
            var message = "I don't know a variable called '\(name)' yet. You can make one with: let \(name) = ..."
            if let suggestion = closestName(to: name, in: env) {
                message += " Did you mean '\(suggestion)'?"
            }
            throw NiflaError(line: line, message: message)

        case .call(let name, let args, let line):
            if builtinTools[name] != nil {
                return try checkBuiltinCall(name: name, args: args, line: line, env: &env, outerNames: outerNames, forgiving: false)
            }
            if let kind = try checkBareToolCall(name: name, args: args, line: line, env: &env, outerNames: outerNames, forgiving: false) {
                return kind
            }
            try checkCall(name: name, args: args, line: line, env: &env, outerNames: outerNames)
            return .unknown

        case .object(let fields, _):
            for field in fields {
                _ = try checkExpr(field.value, env: &env, outerNames: outerNames)
            }
            return .object

        case .list(let items, _):
            for item in items {
                _ = try checkExpr(item, env: &env, outerNames: outerNames)
            }
            return .list

        case .field(let base, _, _):
            _ = try checkExpr(base, env: &env, outerNames: outerNames)
            return .unknown  // what comes out of an object can't be proven

        case .index(let base, let index, let line):
            let baseKind = try checkExpr(base, env: &env, outerNames: outerNames)
            let indexKind = try checkExpr(index, env: &env, outerNames: outerNames)
            try checkIndexKind(base: baseKind, index: indexKind, line: line)
            // A character taken from text is provably text; an item
            // taken from a list could be anything.
            return baseKind == .text ? .text : .unknown

        case .floor(let asm, let args, let line):
            return try checkFloor(asm: asm, args: args, line: line, env: &env, outerNames: outerNames, forgiving: false)

        case .negate(let inner, _):
            let kind = try checkExpr(inner, env: &env, outerNames: outerNames)
            return kind == .number ? .number : .unknown

        case .binary(let leftExpr, let op, let rightExpr, let line):
            let left = try checkExpr(leftExpr, env: &env, outerNames: outerNames)
            let right = try checkExpr(rightExpr, env: &env, outerNames: outerNames)
            return try checkBinary(op: op, left: left, right: right, line: line)
        }
    }

    // The same reading, inside a function body: a variable found
    // nowhere is forgiven when a 'let' for it exists around the
    // function's making (see checkDefine).
    private func checkExprForgiving(_ expr: Expr, env: inout StaticEnv, outerNames: Set<String>) throws -> StaticKind {
        switch expr {
        case .variable(let name, let line):
            if let kind = env.lookup(name) {
                return kind
            }
            if outerNames.contains(name) {
                return .unknown
            }
            var message = "I don't know a variable called '\(name)' yet. You can make one with: let \(name) = ..."
            if let suggestion = closestName(to: name, in: env) {
                message += " Did you mean '\(suggestion)'?"
            }
            throw NiflaError(line: line, message: message)

        case .call(let name, let args, let line):
            if builtinTools[name] != nil {
                return try checkBuiltinCall(name: name, args: args, line: line, env: &env, outerNames: outerNames, forgiving: true)
            }
            if let kind = try checkBareToolCall(name: name, args: args, line: line, env: &env, outerNames: outerNames, forgiving: true) {
                return kind
            }
            try checkCallForgiving(name: name, args: args, line: line, env: &env, outerNames: outerNames)
            return .unknown

        case .object(let fields, _):
            for field in fields {
                _ = try checkExprForgiving(field.value, env: &env, outerNames: outerNames)
            }
            return .object

        case .list(let items, _):
            for item in items {
                _ = try checkExprForgiving(item, env: &env, outerNames: outerNames)
            }
            return .list

        case .field(let base, _, _):
            _ = try checkExprForgiving(base, env: &env, outerNames: outerNames)
            return .unknown

        case .index(let base, let index, let line):
            let baseKind = try checkExprForgiving(base, env: &env, outerNames: outerNames)
            let indexKind = try checkExprForgiving(index, env: &env, outerNames: outerNames)
            try checkIndexKind(base: baseKind, index: indexKind, line: line)
            return baseKind == .text ? .text : .unknown

        case .floor(let asm, let args, let line):
            return try checkFloor(asm: asm, args: args, line: line, env: &env, outerNames: outerNames, forgiving: true)

        case .negate(let inner, _):
            let kind = try checkExprForgiving(inner, env: &env, outerNames: outerNames)
            return kind == .number ? .number : .unknown

        case .binary(let leftExpr, let op, let rightExpr, let line):
            let left = try checkExprForgiving(leftExpr, env: &env, outerNames: outerNames)
            let right = try checkExprForgiving(rightExpr, env: &env, outerNames: outerNames)
            return try checkBinary(op: op, left: left, right: right, line: line)

        default:
            return try checkExpr(expr, env: &env, outerNames: outerNames)
        }
    }

    // An index whose kind is proven: picking an item of a list,
    // a character of some text, or a byte of a block of bytes
    // takes a number, so a proven kind that isn't a number can
    // never work and is refused before the run. (Which items
    // exist — the range — is the run's business, as always.)
    private func checkIndexKind(base: StaticKind, index: StaticKind, line: Int) throws {
        guard base == .list || base == .text || base == .bytes else { return }
        guard index != .unknown && index != .number else { return }
        throw NiflaError(line: line, message: "I can't use \(index.phrase) to pick an item. Items are picked by a whole number — 0 for the first one, 1 for the second, and so on. I caught this before the program ran, so nothing ran.")
    }

    // A floor block (Stones 7 and 9): the checker treats the
    // instructions as opaque — they are the processor's business,
    // not Nifla's — but it does verify the block is well-formed,
    // which here means it isn't empty, and it checks the values
    // the block is handed: each must be a number or a block of
    // bytes, there may be only one block of bytes, and a handed
    // value whose kind is proven to be anything else is refused
    // before the run. What a block gives back can no longer be
    // proven: since Stone 9 it may hand back extra answers, and
    // then it gives a list, not a number — so the kind is unknown
    // and the run's own checks remain the guard.
    private func checkFloor(asm: String, args: [Expr], line: Int, env: inout StaticEnv, outerNames: Set<String>, forgiving: Bool) throws -> StaticKind {
        if asm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw NiflaError(line: line, message: "This floor block is empty — it needs the processor instructions it is meant to run, between the 'floor {' line and the line holding only '}'.")
        }
        var bytesSeen = 0
        for arg in args {
            let kind = forgiving
                ? try checkExprForgiving(arg, env: &env, outerNames: outerNames)
                : try checkExpr(arg, env: &env, outerNames: outerNames)
            if kind == .bytes {
                bytesSeen += 1
                if bytesSeen > 1 {
                    throw NiflaError(line: line, message: "'floor' can be handed only one block of bytes, but it was given two. I caught this before the program ran, so nothing ran.")
                }
            } else if forBareMetal && kind == .text {
                // The bare desk's memory side carries one piece
                // of text; the bare validator counts them.
                continue
            } else if kind != .unknown && kind != .number {
                if forBareMetal {
                    throw NiflaError(line: line, message: "'floor' can be handed numbers and one piece of text on bare metal, but it was given \(kind.phrase). I caught this before the program ran, so nothing ran.")
                }
                throw NiflaError(line: line, message: "'floor' can be handed numbers and one block of bytes, but it was given \(kind.phrase). I caught this before the program ran, so nothing ran.")
            }
        }
        // On bare metal a floor block gives back only its
        // number; hosted, it may give a list of extra answers.
        return forBareMetal ? .number : .unknown
    }

    // The kind rules of the operators, mirroring the interpreter's
    // own: the checker speaks only when BOTH sides' kinds are known
    // and the pairing can never work. ('==' and '!=' never fail —
    // different kinds are simply unequal — so they are never
    // flagged.)
    private func checkBinary(op: String, left: StaticKind, right: StaticKind, line: Int) throws -> StaticKind {
        switch op {
        case "+":
            if left != .unknown && right != .unknown {
                if left == .text || right == .text {
                    return .text
                }
                if left == .number && right == .number {
                    return .number
                }
                throw NiflaError(line: line, message: "I can't add \(left.phrase) and \(right.phrase). '+' adds two numbers, or joins text together. I caught this before the program ran, so nothing ran.")
            }
            if left == .text || right == .text { return .text }
            return .unknown

        case "-", "*", "/":
            if left != .unknown && right != .unknown {
                guard left == .number && right == .number else {
                    let verb = op == "-" ? "subtract" : (op == "*" ? "multiply" : "divide")
                    throw NiflaError(line: line, message: "I can't \(verb) \(left.phrase) and \(right.phrase). '\(op)' works on two numbers. (Only '+' joins text.) I caught this before the program ran, so nothing ran.")
                }
                return .number
            }
            return .number

        case "<", "<=", ">", ">=":
            if left != .unknown && right != .unknown {
                guard left == .number && right == .number else {
                    throw NiflaError(line: line, message: "I can't compare \(left.phrase) and \(right.phrase) with '\(op)'. '\(op)' compares two numbers. (Text and true/false values can be checked with == and !=.) I caught this before the program ran, so nothing ran.")
                }
            }
            return .boolean

        case "==", "!=":
            return .boolean

        default:
            return .unknown
        }
    }

    // "no values", "1 value (name)", "2 values (a, b)" — the same
    // words the interpreter uses for the wrong-number-of-values error.
    private func takesText(_ params: [String]) -> String {
        switch params.count {
        case 0: return "no values"
        case 1: return "1 value (\(params[0]))"
        default: return "\(params.count) values (\(params.joined(separator: ", ")))"
        }
    }

    private func closestFunctionName(to name: String) -> String? {
        var best: (name: String, distance: Int)? = nil
        for candidate in functions.keys.sorted() where candidate != name {
            let distance = editDistance(name, candidate)
            if distance <= 2 && (best == nil || distance < best!.distance) {
                best = (candidate, distance)
            }
        }
        return best?.name
    }

    private func closestName(to name: String, in env: StaticEnv) -> String? {
        var best: (name: String, distance: Int)? = nil
        for candidate in Set(env.allNames()).sorted() where candidate != name {
            let distance = editDistance(name, candidate)
            if distance <= 2 && (best == nil || distance < best!.distance) {
                best = (candidate, distance)
            }
        }
        return best?.name
    }
}
