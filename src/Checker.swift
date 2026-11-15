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
indirect enum StaticKind: Hashable {
    case number
    case text
    case boolean
    case object
    case list
    case bytes
    case unknown
    // Stone 19: the empty value, definitely — a variable proven
    // to hold nothing (made from 'nothing', or narrowed by a
    // check: in the road of 'if x == nothing' where it held).
    case nothing
    // Stone 19: one of these kinds, or nothing — the kind of a
    // value marked 'maybe', not yet checked. The heart of the
    // stone: a maybe may only be used where nothing could be
    // handled, and the checker refuses the uses it can prove
    // would meet the empty value unprepared.
    case maybe(StaticKind)

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
        case .nothing: return "nothing"
        case .maybe(let inner): return "\(inner.phrase) or nothing"
        }
    }

    // Stone 18: the kind an annotation word names, or nil for
    // 'nothing' (which no StaticKind stands for — a promise that
    // a function gives nothing back, checked on its own terms).
    // Stone 19: a 'maybe' word names the maybe of its kind.
    static func fromKindWord(_ word: String) -> StaticKind? {
        if word.hasPrefix("maybe ") {
            return fromKindWord(String(word.dropFirst("maybe ".count))).map { .maybe($0) }
        }
        switch word {
        case "number": return .number
        case "text": return .text
        case "boolean": return .boolean
        case "list": return .list
        case "object": return .object
        case "bytes": return .bytes
        default: return nil
        }
    }

    // How an annotation word itself is phrased in a message.
    static func phrase(forKindWord word: String) -> String {
        if let kind = fromKindWord(word) { return kind.phrase }
        return "nothing"
    }

    // Stone 19: how two proven kinds join where the program
    // could have gone either way (the two sides of an 'if', a
    // loop body against the state before it). Kinds that agree
    // stay; a definite kind meeting the empty value becomes the
    // maybe of that kind — the honest sum of the two roads;
    // anything else that disagrees becomes unknown, as before.
    static func mergedKind(_ a: StaticKind, _ b: StaticKind) -> StaticKind {
        if a == b { return a }
        switch (a, b) {
        case (.nothing, .maybe(let inner)), (.maybe(let inner), .nothing):
            return .maybe(inner)
        case (.nothing, let kind) where kind != .unknown:
            return .maybe(kind)
        case (let kind, .nothing) where kind != .unknown:
            return .maybe(kind)
        case (.maybe(let inner), let kind) where kind == inner:
            return .maybe(inner)
        case (let kind, .maybe(let inner)) where kind == inner:
            return .maybe(inner)
        default:
            return .unknown
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
    "readbytes": BuiltinRule(result: .bytes, needs: [([.text], "the name of a file, as text")]),
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
    // Stone 18: three more pictures, kept scope by scope beside
    // the kinds — the annotation a variable was made with (a
    // promise, not a fact: it survives even when kinds are
    // forgotten), the constant number a variable provably holds,
    // and whether a list variable provably holds an empty list.
    // Facts are held only while they are provable; anything that
    // could change them quietly takes them away.
    private(set) var annotations: [[String: String]] = [[:]]
    private(set) var constants: [[String: Double]] = [[:]]
    private(set) var emptyLists: [[String: Bool]] = [[:]]
    // Stone 18: the exact length of the list or text a variable
    // provably holds (made from a literal of that length and not
    // provably changed since). Held with the same care as the
    // other facts.
    private(set) var lengths: [[String: Int]] = [[:]]

    func lookup(_ name: String) -> StaticKind? {
        for scope in scopes.reversed() {
            if let kind = scope[name] { return kind }
        }
        return nil
    }

    func lookupAnnotation(_ name: String) -> String? {
        for scope in annotations.reversed() {
            if let word = scope[name] { return word }
        }
        return nil
    }

    func lookupConstant(_ name: String) -> Double? {
        for scope in constants.reversed() {
            if let value = scope[name] { return value }
        }
        return nil
    }

    // True only while the list under this name is proven empty:
    // made as [] and not grown, aliased, or handed anywhere the
    // checker can't watch since.
    func isProvenEmpty(_ name: String) -> Bool {
        for scope in emptyLists.reversed() {
            if let empty = scope[name] { return empty }
        }
        return false
    }

    func lookupLength(_ name: String) -> Int? {
        for scope in lengths.reversed() {
            if let length = scope[name] { return length }
        }
        return nil
    }

    func isDeclaredHere(_ name: String) -> Bool {
        scopes.last?[name] != nil
    }

    mutating func declare(_ name: String, _ kind: StaticKind, annotation: String? = nil, constant: Double? = nil, provenEmpty: Bool = false, length: Int? = nil) {
        scopes[scopes.count - 1][name] = kind
        if let annotation {
            annotations[annotations.count - 1][name] = annotation
        }
        if let constant {
            constants[constants.count - 1][name] = constant
        }
        if provenEmpty {
            emptyLists[emptyLists.count - 1][name] = true
        }
        if let length {
            lengths[lengths.count - 1][name] = length
        }
    }

    // Sets the kind in whichever block made the name. Returns false
    // when no block knows the name.
    mutating func assign(_ name: String, _ kind: StaticKind, constant: Double? = nil, provenEmpty: Bool = false, length: Int? = nil) -> Bool {
        for index in scopes.indices.reversed() {
            if scopes[index][name] != nil {
                scopes[index][name] = kind
                constants[index][name] = constant
                if provenEmpty {
                    emptyLists[index][name] = true
                } else {
                    emptyLists[index][name] = nil
                }
                lengths[index][name] = length
                return true
            }
        }
        return false
    }

    // Stone 19: sets a name's kind in whichever block made it,
    // and lets its tracked facts go — the narrowing a check
    // against 'nothing' earns (inside 'if x == nothing', x is
    // known to be the empty value; in the 'else', known to be
    // the kind itself). The facts were proven of the unnarrowed
    // value, so they don't carry into the narrowed road.
    mutating func narrow(_ name: String, to kind: StaticKind) {
        for index in scopes.indices.reversed() {
            if scopes[index][name] != nil {
                scopes[index][name] = kind
                constants[index][name] = nil
                emptyLists[index][name] = nil
                lengths[index][name] = nil
                return
            }
        }
    }

    // Takes away every tracked fact in every scope, keeping
    // kinds and annotations. Used when a function body is
    // checked: a fact about a variable outside the body (this
    // global is 0, that list is empty) can be made false by
    // another function before this one is ever called, so
    // inside a body only facts the body itself establishes
    // are provable.
    mutating func dropFacts() {
        constants = constants.map { _ in [:] }
        emptyLists = emptyLists.map { _ in [:] }
        lengths = lengths.map { _ in [:] }
    }

    // Takes away the facts (not the kind, not the annotation) for
    // one name — used when a list is handed somewhere it could be
    // grown out of the checker's sight, or changed by a tool.
    mutating func forgetFacts(about name: String) {
        for index in scopes.indices.reversed() {
            if scopes[index][name] != nil {
                constants[index][name] = nil
                emptyLists[index][name] = nil
                lengths[index][name] = nil
                return
            }
        }
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
        annotations.append([:])
        constants.append([:])
        emptyLists.append([:])
        lengths.append([:])
    }

    mutating func popScope() {
        scopes.removeLast()
        annotations.removeLast()
        constants.removeLast()
        emptyLists.removeLast()
        lengths.removeLast()
    }

    // After a function call, a function may have set any variable it
    // can reach, to anything. Forget every proven kind; keep the
    // names (they were still made). Stone 18: the facts go too —
    // but annotations stay, because they are promises the runtime
    // still guards, not facts the checker proved.
    mutating func forgetKinds() {
        for index in scopes.indices {
            for name in scopes[index].keys {
                scopes[index][name] = .unknown
            }
            constants[index] = [:]
            emptyLists[index] = [:]
            lengths[index] = [:]
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
                    scope[name] = StaticKind.mergedKind(kindA, kindB)
                } else if let kind = kindA ?? kindB {
                    scope[name] = kind
                }
            }
            result.scopes[index] = scope
            // Annotations are the same promise on both ways (they
            // come from the one 'let' that made the name).
            var anns: [String: String] = [:]
            for name in Set(a.annotations[index].keys).union(b.annotations[index].keys) {
                anns[name] = a.annotations[index][name] ?? b.annotations[index][name]
            }
            result.annotations[index] = anns
            // A constant survives only when both ways hold the
            // same number; an empty list only when both ways agree
            // it is still empty.
            var consts: [String: Double] = [:]
            for name in Set(a.constants[index].keys).union(b.constants[index].keys) {
                if let va = a.constants[index][name], let vb = b.constants[index][name], va == vb {
                    consts[name] = va
                }
            }
            result.constants[index] = consts
            var empties: [String: Bool] = [:]
            for name in Set(a.emptyLists[index].keys).union(b.emptyLists[index].keys) {
                if a.emptyLists[index][name] == true && b.emptyLists[index][name] == true {
                    empties[name] = true
                }
            }
            result.emptyLists[index] = empties
            // A length survives only when both ways agree on it.
            var lens: [String: Int] = [:]
            for name in Set(a.lengths[index].keys).union(b.lengths[index].keys) {
                if let la = a.lengths[index][name], let lb = b.lengths[index][name], la == lb {
                    lens[name] = la
                }
            }
            result.lengths[index] = lens
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
    private var functions: [String: (params: [String], paramKinds: [String?], returnKind: String?)] = [:]

    // Stone 18: while a function body is being checked, the
    // promise its 'make' line made about what it gives back —
    // so 'give' lines inside it can be checked against it.
    private var currentReturnKind: String? = nil
    private var currentFunctionName: String? = nil

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
            case .define(let name, let params, let paramKinds, let returnKind, let body, _):
                if functions[name] == nil { functions[name] = (params: params, paramKinds: paramKinds, returnKind: returnKind) }
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
            if case .declare(let name, _, _, _) = statement {
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
        case .declare(let name, let kindWord, let valueExpr, let line):
            let kind = try checkExpr(valueExpr, env: &env, outerNames: outerNames)
            if let kindWord {
                try checkAnnotation(kindWord: kindWord, proven: kind, line: line, wording: "'\(name)' is marked as \(StaticKind.phrase(forKindWord: kindWord)) by its annotation, but this value is \(kind.phrase). Change the value, or change the annotation.")
            }
            let constant = constNumber(valueExpr, in: env)
            let provenEmpty = isEmptyListExpr(valueExpr, in: env)
            noteAliasing(of: valueExpr, env: &env)
            env.declare(name, declaredKind(kindWord: kindWord, proven: kind), annotation: kindWord, constant: constant, provenEmpty: provenEmpty, length: literalLength(of: valueExpr))

        case .assign(let name, let valueExpr, let line):
            // The interpreter works the value out first, then looks
            // for the variable — so the checker reads in that order.
            let kind = try checkExpr(valueExpr, env: &env, outerNames: outerNames)
            if env.lookup(name) == nil {
                throw NiflaError(line: line, message: "I can't set '\(name)', because no variable called '\(name)' has been made yet. Make one first with: let \(name) = ...")
            }
            if let kindWord = env.lookupAnnotation(name) {
                try checkAnnotation(kindWord: kindWord, proven: kind, line: line, wording: "'\(name)' is marked as \(StaticKind.phrase(forKindWord: kindWord)) by its annotation, but this value is \(kind.phrase). Change the value, or change the annotation.")
            }
            let constant = constNumber(valueExpr, in: env)
            let provenEmpty = isEmptyListExpr(valueExpr, in: env)
            noteAliasing(of: valueExpr, env: &env)
            _ = env.assign(name, declaredKind(kindWord: env.lookupAnnotation(name), proven: kind), constant: constant, provenEmpty: provenEmpty, length: literalLength(of: valueExpr))

        case .assignTarget(let target, let valueExpr, _):
            _ = try checkExpr(target, env: &env, outerNames: outerNames)
            _ = try checkExpr(valueExpr, env: &env, outerNames: outerNames)

        case .say(let valueExpr, _):
            _ = try checkExpr(valueExpr, env: &env, outerNames: outerNames)

        case .ifElse(let condition, let thenBlock, let elseBlock, _):
            _ = try checkExpr(condition, env: &env, outerNames: outerNames)
            // Stone 19: a test against 'nothing' narrows the
            // tested variable on each road (see nothingTest).
            let test = nothingTest(condition: condition, env: env)
            let before = env
            if let test { env.narrow(test.name, to: test.thenKind) }
            try checkChildBlock(thenBlock, env: &env, outerNames: outerNames, mergeWithBefore: false)
            let afterThen = env
            env = before
            if let test { env.narrow(test.name, to: test.elseKind) }
            if let elseBlock {
                try checkChildBlock(elseBlock, env: &env, outerNames: outerNames, mergeWithBefore: false)
            }
            env = StaticEnv.merged(afterThen, env)

        case .whileLoop(let condition, let body, _):
            _ = try checkExpr(condition, env: &env, outerNames: outerNames)
            // Stone 19: inside the loop the test held, so the
            // tested variable is narrowed to the road where it
            // held; after the loop it is narrowed to the road
            // where it failed — the only way out.
            let test = nothingTest(condition: condition, env: env)
            if let test { env.narrow(test.name, to: test.thenKind) }
            try checkChildBlock(body, env: &env, outerNames: outerNames, mergeWithBefore: true)
            if let test { env.narrow(test.name, to: test.elseKind) }

        case .repeatLoop(let count, let body, let line):
            let countKind = try checkExpr(count, env: &env, outerNames: outerNames)
            try checkRepeatCount(count, env: env, line: line)
            try checkCountKind(kind: countKind, line: line)
            try checkChildBlock(body, env: &env, outerNames: outerNames, mergeWithBefore: true)

        case .forEach(let name, let over, let body, let line):
            let overKind = try checkExpr(over, env: &env, outerNames: outerNames)
            try checkWalkKind(kind: overKind, line: line)
            let before = env
            env.pushScope()
            env.declare(name, .unknown)
            try checkBlock(body, env: &env, outerNames: outerNames)
            env.popScope()
            env = StaticEnv.merged(before, env)

        case .define(let name, let params, let paramKinds, let returnKind, let body, _):
            try checkDefine(name: name, params: params, paramKinds: paramKinds, returnKind: returnKind, body: body, env: env, outerNames: outerNames)

        case .give(let valueExpr, let line):
            let kind = try checkExpr(valueExpr, env: &env, outerNames: outerNames)
            try checkGive(kind: kind, line: line)

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
    private func checkDefine(name: String, params: [String], paramKinds: [String?], returnKind: String?, body: [Stmt], env: StaticEnv, outerNames: Set<String>) throws {
        var bodyEnv = env
        // Stone 18: kinds and annotations carry into the body;
        // tracked facts do not (see dropFacts).
        bodyEnv.dropFacts()
        bodyEnv.pushScope()
        for (index, param) in params.enumerated() {
            // Stone 18: an annotated parameter is a promise the
            // body is checked against — its kind is known inside,
            // the way a literal's would be. An unannotated one
            // stays unknown, as before.
            let kindWord = index < paramKinds.count ? paramKinds[index] : nil
            bodyEnv.declare(param, declaredKind(kindWord: kindWord, proven: .unknown), annotation: kindWord)
        }
        let bodyOuter = outerNames.union(declaredNames(in: body))
        let savedReturnKind = currentReturnKind
        let savedFunctionName = currentFunctionName
        currentReturnKind = returnKind
        currentFunctionName = name
        for statement in body {
            try checkStatementInFunction(statement, env: &bodyEnv, outerNames: bodyOuter)
        }
        currentReturnKind = savedReturnKind
        currentFunctionName = savedFunctionName
    }

    // Statements inside a function body are checked like any others,
    // except that a variable name found nowhere is forgiven when a
    // 'let' for it exists in a block around the function's making
    // (it will have run by the time the function is called). Nested
    // function makings keep the same forgiveness.
    private func checkStatementInFunction(_ statement: Stmt, env: inout StaticEnv, outerNames: Set<String>) throws {
        switch statement {
        case .define(let name, let params, let paramKinds, let returnKind, let body, _):
            try checkDefine(name: name, params: params, paramKinds: paramKinds, returnKind: returnKind, body: body, env: env, outerNames: outerNames)
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
        case .declare(let name, let kindWord, let valueExpr, let line):
            let kind = try checkExprForgiving(valueExpr, env: &env, outerNames: outerNames)
            if let kindWord {
                try checkAnnotation(kindWord: kindWord, proven: kind, line: line, wording: "'\(name)' is marked as \(StaticKind.phrase(forKindWord: kindWord)) by its annotation, but this value is \(kind.phrase). Change the value, or change the annotation.")
            }
            let constant = constNumber(valueExpr, in: env)
            let provenEmpty = isEmptyListExpr(valueExpr, in: env)
            noteAliasing(of: valueExpr, env: &env)
            env.declare(name, declaredKind(kindWord: kindWord, proven: kind), annotation: kindWord, constant: constant, provenEmpty: provenEmpty, length: literalLength(of: valueExpr))

        case .assign(let name, let valueExpr, let line):
            let kind = try checkExprForgiving(valueExpr, env: &env, outerNames: outerNames)
            if env.lookup(name) == nil && !outerNames.contains(name) {
                throw NiflaError(line: line, message: "I can't set '\(name)', because no variable called '\(name)' has been made yet. Make one first with: let \(name) = ...")
            }
            if let kindWord = env.lookupAnnotation(name) {
                try checkAnnotation(kindWord: kindWord, proven: kind, line: line, wording: "'\(name)' is marked as \(StaticKind.phrase(forKindWord: kindWord)) by its annotation, but this value is \(kind.phrase). Change the value, or change the annotation.")
            }
            let constant = constNumber(valueExpr, in: env)
            let provenEmpty = isEmptyListExpr(valueExpr, in: env)
            noteAliasing(of: valueExpr, env: &env)
            _ = env.assign(name, declaredKind(kindWord: env.lookupAnnotation(name), proven: kind), constant: constant, provenEmpty: provenEmpty, length: literalLength(of: valueExpr))

        case .assignTarget(let target, let valueExpr, _):
            _ = try checkExprForgiving(target, env: &env, outerNames: outerNames)
            _ = try checkExprForgiving(valueExpr, env: &env, outerNames: outerNames)

        case .say(let valueExpr, _):
            _ = try checkExprForgiving(valueExpr, env: &env, outerNames: outerNames)

        case .ifElse(let condition, let thenBlock, let elseBlock, _):
            _ = try checkExprForgiving(condition, env: &env, outerNames: outerNames)
            // Stone 19: narrowing, as in the plain reading.
            let test = nothingTest(condition: condition, env: env)
            let before = env
            if let test { env.narrow(test.name, to: test.thenKind) }
            try checkChildBlockInFunction(thenBlock, env: &env, outerNames: outerNames)
            let afterThen = env
            env = before
            if let test { env.narrow(test.name, to: test.elseKind) }
            if let elseBlock {
                try checkChildBlockInFunction(elseBlock, env: &env, outerNames: outerNames)
            }
            env = StaticEnv.merged(afterThen, env)

        case .whileLoop(let condition, let body, _):
            _ = try checkExprForgiving(condition, env: &env, outerNames: outerNames)
            // Stone 19: narrowing, as in the plain reading —
            // the body sees the road where the test held, and
            // what follows sees the road where it failed.
            let test = nothingTest(condition: condition, env: env)
            let before = env
            if let test { env.narrow(test.name, to: test.thenKind) }
            try checkChildBlockInFunction(body, env: &env, outerNames: outerNames)
            env = StaticEnv.merged(before, env)
            if let test { env.narrow(test.name, to: test.elseKind) }

        case .repeatLoop(let count, let body, let line):
            let countKind = try checkExprForgiving(count, env: &env, outerNames: outerNames)
            try checkRepeatCount(count, env: env, line: line)
            try checkCountKind(kind: countKind, line: line)
            let before = env
            try checkChildBlockInFunction(body, env: &env, outerNames: outerNames)
            env = StaticEnv.merged(before, env)

        case .forEach(let name, let over, let body, let line):
            let overKind = try checkExprForgiving(over, env: &env, outerNames: outerNames)
            try checkWalkKind(kind: overKind, line: line)
            let before = env
            env.pushScope()
            env.declare(name, .unknown)
            let outer = outerNames.union(declaredNames(in: body))
            for inner in body {
                try checkStatementInFunction(inner, env: &env, outerNames: outer)
            }
            env.popScope()
            env = StaticEnv.merged(before, env)

        case .define(let name, let params, let paramKinds, let returnKind, let body, _):
            try checkDefine(name: name, params: params, paramKinds: paramKinds, returnKind: returnKind, body: body, env: env, outerNames: outerNames)

        case .give(let valueExpr, let line):
            let kind = try checkExprForgiving(valueExpr, env: &env, outerNames: outerNames)
            try checkGive(kind: kind, line: line)

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
                var message = "'\(name)' needs \(need.need), but it was given \(kind.phrase)."
                if isMaybe(kind) {
                    message += " A value that may be nothing has to be checked first: if value == nothing { ... } else { ... } — in the 'else', the value is known to be there."
                }
                throw NiflaError(line: line, message: message + " I caught this before the program ran, so nothing ran.")
            }
        }
        // Stone 18: the ranges the checker can prove, and the
        // facts the list tools change.
        try checkBuiltinRanges(name: name, args: args, env: env, line: line)
        if name == "append" || name == "insertat" || name == "removeat" {
            if case .variable(let listName, _) = args[0] {
                env.forgetFacts(about: listName)
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
        guard let record = functions[name] else {
            var message = "I don't know a function called '\(name)' yet. You can make one with: make \(name)(...) { ... }"
            if let suggestion = closestFunctionName(to: name) {
                message += " Did you mean '\(suggestion)'?"
            }
            throw NiflaError(line: line, message: message)
        }
        var argKinds: [StaticKind] = []
        for arg in args {
            argKinds.append(try checkExpr(arg, env: &env, outerNames: outerNames))
        }
        guard args.count == record.params.count else {
            throw NiflaError(line: line, message: "The function '\(name)' takes \(takesText(record.params)), but it was given \(args.count). Make the call match how the function was made: \(name)(\(record.params.joined(separator: ", "))).")
        }
        try checkCallAnnotations(name: name, record: record, argKinds: argKinds, line: line)
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
        guard let record = functions[name] else {
            var message = "I don't know a function called '\(name)' yet. You can make one with: make \(name)(...) { ... }"
            if let suggestion = closestFunctionName(to: name) {
                message += " Did you mean '\(suggestion)'?"
            }
            throw NiflaError(line: line, message: message)
        }
        var argKinds: [StaticKind] = []
        for arg in args {
            argKinds.append(try checkExprForgiving(arg, env: &env, outerNames: outerNames))
        }
        guard args.count == record.params.count else {
            throw NiflaError(line: line, message: "The function '\(name)' takes \(takesText(record.params)), but it was given \(args.count). Make the call match how the function was made: \(name)(\(record.params.joined(separator: ", "))).")
        }
        try checkCallAnnotations(name: name, record: record, argKinds: argKinds, line: line)
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
        case .nothing:
            return .nothing

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
            // Stone 18: a function that promised a kind gives
            // that kind provably — its callers can be checked
            // against the promise.
            if let returnKind = functions[name]?.returnKind, let kind = StaticKind.fromKindWord(returnKind) {
                return kind
            }
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

        case .field(let base, let fieldName, let line):
            let baseKind = try checkExpr(base, env: &env, outerNames: outerNames)
            try checkFieldBase(base: baseKind, fieldName: fieldName, line: line)
            return .unknown  // what comes out of an object can't be proven

        case .index(let base, let index, let line):
            let baseKind = try checkExpr(base, env: &env, outerNames: outerNames)
            let indexKind = try checkExpr(index, env: &env, outerNames: outerNames)
            try checkIndexKind(base: baseKind, index: indexKind, line: line)
            try checkIndexRange(base: base, baseKind: baseKind, index: index, env: env, line: line)
            // A character taken from text is provably text; an item
            // taken from a list could be anything.
            return baseKind == .text ? .text : .unknown

        case .floor(let asm, let args, let line):
            return try checkFloor(asm: asm, args: args, line: line, env: &env, outerNames: outerNames, forgiving: false)

        case .negate(let inner, let line):
            let kind = try checkExpr(inner, env: &env, outerNames: outerNames)
            try checkNegate(kind: kind, line: line)
            return kind == .number ? .number : .unknown

        case .binary(let leftExpr, let op, let rightExpr, let line):
            let left = try checkExpr(leftExpr, env: &env, outerNames: outerNames)
            let right = try checkExpr(rightExpr, env: &env, outerNames: outerNames)
            try checkDivisor(op: op, right: rightExpr, env: env, line: line)
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
            if let returnKind = functions[name]?.returnKind, let kind = StaticKind.fromKindWord(returnKind) {
                return kind
            }
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

        case .field(let base, let fieldName, let line):
            let baseKind = try checkExprForgiving(base, env: &env, outerNames: outerNames)
            try checkFieldBase(base: baseKind, fieldName: fieldName, line: line)
            return .unknown

        case .index(let base, let index, let line):
            let baseKind = try checkExprForgiving(base, env: &env, outerNames: outerNames)
            let indexKind = try checkExprForgiving(index, env: &env, outerNames: outerNames)
            try checkIndexKind(base: baseKind, index: indexKind, line: line)
            try checkIndexRange(base: base, baseKind: baseKind, index: index, env: env, line: line)
            return baseKind == .text ? .text : .unknown

        case .floor(let asm, let args, let line):
            return try checkFloor(asm: asm, args: args, line: line, env: &env, outerNames: outerNames, forgiving: true)

        case .negate(let inner, let line):
            let kind = try checkExprForgiving(inner, env: &env, outerNames: outerNames)
            try checkNegate(kind: kind, line: line)
            return kind == .number ? .number : .unknown

        case .binary(let leftExpr, let op, let rightExpr, let line):
            let left = try checkExprForgiving(leftExpr, env: &env, outerNames: outerNames)
            let right = try checkExprForgiving(rightExpr, env: &env, outerNames: outerNames)
            try checkDivisor(op: op, right: rightExpr, env: env, line: line)
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
        // Stone 19: the empty value has no items, and can't
        // pick one; a maybe must be checked before either use.
        if base == .nothing {
            throw NiflaError(line: line, message: "I can't take an item from nothing. Only a list or some text has items to take from — like [1, 2, 3], where [0] takes the first item, or \"abc\", where [0] takes the first character. I caught this before the program ran, so nothing ran.")
        }
        if isMaybe(base) {
            throw unhandledMaybeError(kind: base, line: line)
        }
        if index == .nothing {
            throw NiflaError(line: line, message: "I can't use nothing to pick an item. Items are picked by a whole number — 0 for the first one, 1 for the second, and so on. I caught this before the program ran, so nothing ran.")
        }
        if isMaybe(index) {
            throw unhandledMaybeError(kind: index, line: line)
        }
        guard base == .list || base == .text || base == .bytes else { return }
        guard index != .unknown && index != .number else { return }
        throw NiflaError(line: line, message: "I can't use \(index.phrase) to pick an item. Items are picked by a whole number — 0 for the first one, 1 for the second, and so on. I caught this before the program ran, so nothing ran.")
    }

    // Stone 19: reading a field of the empty value, or of a
    // value that may be it, can never work — only an object has
    // fields. (A field read from any other proven kind is the
    // run's business, as it always has been.)
    private func checkFieldBase(base: StaticKind, fieldName: String, line: Int) throws {
        if base == .nothing {
            throw NiflaError(line: line, message: "I can't read the field '\(fieldName)' of nothing, because only an object has fields. Make an object first, like: let person = { name: \"Tyler\" } — then person.\(fieldName) works. I caught this before the program ran, so nothing ran.")
        }
        if isMaybe(base) {
            throw unhandledMaybeError(kind: base, line: line)
        }
    }

    // Stone 19: a 'repeat' count that is the empty value, or
    // may be it, can never count — in the run's own words.
    private func checkCountKind(kind: StaticKind, line: Int) throws {
        if kind == .nothing {
            throw NiflaError(line: line, message: "'repeat' needs a number saying how many times to run, but here it was given nothing. Write it like: repeat 3 { ... } I caught this before the program ran, so nothing ran.")
        }
        if isMaybe(kind) {
            throw unhandledMaybeError(kind: kind, line: line)
        }
    }

    // Stone 19: a 'for' walk over the empty value, or over a
    // value that may be it, has nothing to walk — in the run's
    // own words.
    private func checkWalkKind(kind: StaticKind, line: Int) throws {
        if kind == .nothing {
            throw NiflaError(line: line, message: "'for' needs a list, some text, or a block of bytes to walk through, but here it was given nothing. Write it like: for item in items { ... } I caught this before the program ran, so nothing ran.")
        }
        if isMaybe(kind) {
            throw unhandledMaybeError(kind: kind, line: line)
        }
    }

    // Stone 19: a minus sign in front of the empty value, or of
    // a value that may be it, can never work.
    private func checkNegate(kind: StaticKind, line: Int) throws {
        if kind == .nothing {
            throw NiflaError(line: line, message: "I can only put a minus sign in front of a number, but here it was in front of nothing. I caught this before the program ran, so nothing ran.")
        }
        if isMaybe(kind) {
            throw unhandledMaybeError(kind: kind, line: line)
        }
    }

    // Stone 19: when a condition tests a 'maybe' variable
    // against 'nothing', the two roads know more than the
    // variable's kind alone says: on the road where the test
    // held, the variable is the empty value (for '==') or the
    // kind itself (for '!='); on the other road, the opposite.
    // Returns the variable's name and the kind each road may
    // narrow it to, or nil when the condition has another
    // shape — narrowing is earned only by this plain test.
    private func nothingTest(condition: Expr, env: StaticEnv) -> (name: String, thenKind: StaticKind, elseKind: StaticKind)? {
        guard case .binary(let a, let op, let b, _) = condition, op == "==" || op == "!=" else { return nil }
        for (varSide, otherSide) in [(a, b), (b, a)] {
            guard case .variable(let name, _) = varSide,
                  let kind = env.lookup(name) else { continue }
            // The maybe the variable answers to: its proven
            // kind, when that is a maybe — or its annotation,
            // when the value it provably holds right now is one
            // of the maybe's two roads (a 'maybe number'
            // variable made from 'nothing' is proven to hold
            // the empty value, but the mark still promises the
            // number road is the other way it can go).
            var inner: StaticKind? = nil
            if case .maybe(let flowInner) = kind {
                inner = flowInner
            } else if let word = env.lookupAnnotation(name),
                      let marked = StaticKind.fromKindWord(word),
                      case .maybe(let markedInner) = marked,
                      kind == .nothing || kind == markedInner {
                inner = markedInner
            }
            guard let inner else { continue }
            let otherIsNothing: Bool
            if case .nothing = otherSide {
                otherIsNothing = true
            } else if case .variable(let otherName, _) = otherSide, env.lookup(otherName) == .nothing {
                otherIsNothing = true
            } else {
                otherIsNothing = false
            }
            guard otherIsNothing else { continue }
            if op == "==" {
                return (name: name, thenKind: .nothing, elseKind: inner)
            }
            return (name: name, thenKind: inner, elseKind: .nothing)
        }
        return nil
    }

    // MARK: Stone 18 — annotations and provable ranges

    // The kind a name is recorded under: an annotation's kind
    // when there is one, otherwise the kind the value was
    // proven to have. Stone 19: a proven kind that satisfies
    // the annotation is the more precise record, and is kept —
    // a 'maybe number' variable proven to hold a number right
    // now is recorded as a number, until something that may be
    // nothing is set into it. A 'nothing' mark records the
    // empty kind itself: the guard at the boundary sees to it
    // that nothing else can ever stand there.
    private func declaredKind(kindWord: String?, proven: StaticKind) -> StaticKind {
        guard let kindWord else { return proven }
        if kindWord == "nothing" { return .nothing }
        guard let wanted = StaticKind.fromKindWord(kindWord) else { return .unknown }
        if proven != .unknown && annotationSatisfied(proven: proven, wanted: wanted) {
            return proven
        }
        return wanted
    }

    // Stone 19: whether a proven kind satisfies an annotation's
    // kind — the kind itself, or, for a 'maybe' mark, the kind
    // it names or the empty value.
    private func annotationSatisfied(proven: StaticKind, wanted: StaticKind) -> Bool {
        if proven == wanted { return true }
        if case .maybe(let inner) = wanted {
            return proven == inner || proven == .nothing
        }
        return false
    }

    // Whether a proven kind is a 'maybe' — a value that may be
    // the empty value.
    private func isMaybe(_ kind: StaticKind) -> Bool {
        if case .maybe = kind { return true }
        return false
    }

    // Stone 19: the refusal for a use of a value that may be
    // nothing, where a value that is surely there is needed.
    private func unhandledMaybeError(kind: StaticKind, line: Int) -> NiflaError {
        NiflaError(line: line, message: "This uses \(kind.phrase) — a value that may be nothing — where a value that is surely there is needed, and nothing is the empty value: there is nothing there to use. Check the value first, like: if value == nothing { ... } else { ... } — in the 'else', the value is known to be there. I caught this before the program ran, so nothing ran.")
    }

    // Refuses when a proven kind can never satisfy an
    // annotation. Stays silent when the kind can't be proven —
    // the runtime guard at the boundary is the keeper there.
    private func checkAnnotation(kindWord: String, proven: StaticKind, line: Int, wording: String) throws {
        if kindWord == "nothing" {
            // Stone 19: the empty value itself satisfies a
            // 'nothing' mark now; any proven value besides it
            // never can.
            if proven != .unknown && proven != .nothing {
                throw NiflaError(line: line, message: wording + " I caught this before the program ran, so nothing ran.")
            }
            return
        }
        guard let wanted = StaticKind.fromKindWord(kindWord) else { return }
        if proven != .unknown && !annotationSatisfied(proven: proven, wanted: wanted) {
            throw NiflaError(line: line, message: wording + " I caught this before the program ran, so nothing ran.")
        }
    }

    // The annotation check at a call: each handed value whose
    // kind is proven against the parameter it lands in.
    private func checkCallAnnotations(name: String, record: (params: [String], paramKinds: [String?], returnKind: String?), argKinds: [StaticKind], line: Int) throws {
        for (index, kindWord) in record.paramKinds.enumerated() {
            guard let kindWord, index < argKinds.count else { continue }
            let proven = argKinds[index]
            guard proven != .unknown else { continue }
            try checkAnnotation(kindWord: kindWord, proven: proven, line: line, wording: "The value handed to '\(name)' for '\(record.params[index])' is \(proven.phrase), but '\(record.params[index])' is marked as \(StaticKind.phrase(forKindWord: kindWord)) by its annotation. Change what the call hands over, or change the annotation.")
        }
    }

    // The annotation check at a 'give': the value handed back,
    // against the promise on the function's 'make' line.
    private func checkGive(kind: StaticKind, line: Int) throws {
        guard let returnKind = currentReturnKind, let fname = currentFunctionName else { return }
        try checkAnnotation(kindWord: returnKind, proven: kind, line: line, wording: "'\(fname)' is marked to give back \(StaticKind.phrase(forKindWord: returnKind)) by its annotation, but this 'give' hands back \(kind.phrase). Change the value, or change the annotation.")
    }

    // A 'repeat' count the checker can prove is negative.
    private func checkRepeatCount(_ count: Expr, env: StaticEnv, line: Int) throws {
        if let value = constNumber(count, in: env), value < 0 {
            throw NiflaError(line: line, message: "'repeat' was told to run \(formatNumber(value)) times, but a count can't be negative — a loop can't run less than zero times. Use zero or more, like: repeat 3 { ... } I caught this before the program ran, so nothing ran.")
        }
    }

    // A division whose second number the checker can prove is
    // zero. (Nifla has no modulo sign; '/' is the only divisor.)
    private func checkDivisor(op: String, right: Expr, env: StaticEnv, line: Int) throws {
        guard op == "/" else { return }
        if let value = constNumber(right, in: env), value == 0 {
            throw NiflaError(line: line, message: "I can't divide by zero. Dividing needs a second number that isn't zero. I caught this before the program ran, so nothing ran.")
        }
    }

    // An index the checker can prove lands outside: a literal
    // text or list carries its length on its face; a list
    // variable proven empty refuses any index; a negative whole
    // index can never pick from anything.
    private func checkIndexRange(base: Expr, baseKind: StaticKind, index: Expr, env: StaticEnv, line: Int) throws {
        let raw = constNumber(index, in: env)
        let whole: Int? = raw.flatMap { $0 == $0.rounded() && abs($0) < 1e15 ? Int($0) : nil }
        let suffix = " I caught this before the program ran, so nothing ran."
        if case .text(let text, _) = base {
            let length = text.count
            if length == 0 {
                if let i = whole {
                    throw NiflaError(line: line, message: "This text has no characters yet, so there is no character \(i) to take from it." + suffix)
                }
                throw NiflaError(line: line, message: "This text is empty — it has no characters — so no number can pick a character from it." + suffix)
            }
            if let i = whole, i < 0 || i >= length {
                throw NiflaError(line: line, message: "This text has \(length) characters, numbered 0 to \(length - 1), but I was asked for character \(i)." + suffix)
            }
            return
        }
        if case .list(let items, _) = base {
            if items.isEmpty {
                if let i = whole {
                    throw NiflaError(line: line, message: "This list has no items yet, so there is no item \(i) to take from it. Items can be added with append — like: append(items, ...)." + suffix)
                }
                throw NiflaError(line: line, message: "This list is empty — it has no items — so no number can pick an item from it. Items can be added with append — like: append(items, ...)." + suffix)
            }
            if let i = whole, i < 0 || i >= items.count {
                throw NiflaError(line: line, message: "This list has \(items.count) items, numbered 0 to \(items.count - 1), but I was asked for item \(i)." + suffix)
            }
            return
        }
        if case .variable(let name, _) = base, baseKind == .list, env.isProvenEmpty(name) {
            if let i = whole {
                throw NiflaError(line: line, message: "This list has no items yet, so there is no item \(i) to take from it. Items can be added with append — like: append(items, ...)." + suffix)
            }
            throw NiflaError(line: line, message: "This list is empty — it has no items — so no number can pick an item from it. Items can be added with append — like: append(items, ...)." + suffix)
        }
        // A variable whose list or text length is tracked (it
        // was made from a literal of that length and nothing
        // provably changed it since).
        if case .variable(let name, _) = base, let length = env.lookupLength(name), baseKind == .list || baseKind == .text {
            if length == 0 {
                if baseKind == .text {
                    if let i = whole {
                        throw NiflaError(line: line, message: "This text has no characters yet, so there is no character \(i) to take from it." + suffix)
                    }
                    throw NiflaError(line: line, message: "This text is empty — it has no characters — so no number can pick a character from it." + suffix)
                }
                if let i = whole {
                    throw NiflaError(line: line, message: "This list has no items yet, so there is no item \(i) to take from it. Items can be added with append — like: append(items, ...)." + suffix)
                }
                throw NiflaError(line: line, message: "This list is empty — it has no items — so no number can pick an item from it. Items can be added with append — like: append(items, ...)." + suffix)
            }
            if let i = whole, i < 0 || i >= length {
                if baseKind == .text {
                    throw NiflaError(line: line, message: "This text has \(length) characters, numbered 0 to \(length - 1), but I was asked for character \(i)." + suffix)
                }
                throw NiflaError(line: line, message: "This list has \(length) items, numbered 0 to \(length - 1), but I was asked for item \(i)." + suffix)
            }
            return
        }
        if let i = whole, i < 0, baseKind == .list || baseKind == .text || baseKind == .bytes {
            throw NiflaError(line: line, message: "Items are numbered starting at 0, so item \(i) can never be taken — there is nothing before the first one." + suffix)
        }
    }

    // The ranges of the built-in tools that the checker can
    // prove from literals and tracked facts: makebytes' count,
    // exitwith's parting number, removeat on a list proven
    // empty or of literal length, and part's span over a
    // literal text. Each refusal speaks in the run's own words.
    private func checkBuiltinRanges(name: String, args: [Expr], env: StaticEnv, line: Int) throws {
        let suffix = " I caught this before the program ran, so nothing ran."
        switch name {
        case "makebytes":
            guard args.count == 1, let value = constNumber(args[0], in: env) else { return }
            if value < 0 {
                throw NiflaError(line: line, message: "'makebytes' was told to make \(formatNumber(value)) bytes, but a count can't be less than 0." + suffix)
            }
            if value > 16_777_216 {
                throw NiflaError(line: line, message: "'makebytes' was told to make \(formatNumber(value)) bytes, but one block can hold at most 16777216 bytes." + suffix)
            }
        case "exitwith":
            guard args.count == 1, let value = constNumber(args[0], in: env) else { return }
            if value != value.rounded() || value < 0 || value > 255 {
                throw NiflaError(line: line, message: "'exitwith' needs a whole number from 0 to 255, but it was given \(formatNumber(value))." + suffix)
            }
        case "removeat":
            guard args.count == 2 else { return }
            let raw = constNumber(args[1], in: env)
            let whole: Int? = raw.flatMap { $0 == $0.rounded() && abs($0) < 1e15 ? Int($0) : nil }
            var length: Int? = nil
            var provenEmpty = false
            if case .list(let items, _) = args[0] {
                length = items.count
                provenEmpty = items.isEmpty
            } else if case .variable(let listName, _) = args[0] {
                provenEmpty = env.isProvenEmpty(listName)
                length = env.lookupLength(listName)
            }
            if provenEmpty {
                if let i = whole {
                    throw NiflaError(line: line, message: "This list has no items yet, so there is no item \(i) to remove." + suffix)
                }
                throw NiflaError(line: line, message: "This list is empty — it has no items — so there is no item to remove from it." + suffix)
            }
            if let length, let i = whole, i < 0 || i >= length {
                throw NiflaError(line: line, message: "This list has \(length) items, numbered 0 to \(length - 1), but I was asked to remove item \(i)." + suffix)
            }
        case "part":
            guard args.count == 3, case .text(let text, _) = args[0] else { return }
            let length = text.count
            let start = constNumber(args[1], in: env).flatMap { $0 == $0.rounded() && abs($0) < 1e15 ? Int($0) : nil }
            let count = constNumber(args[2], in: env).flatMap { $0 == $0.rounded() && abs($0) < 1e15 ? Int($0) : nil }
            if let s = start, s < 0 {
                throw NiflaError(line: line, message: "'part' was told to start at character \(s), but the first character is number 0 — a start can't be less than 0." + suffix)
            }
            if let c = count, c < 0 {
                throw NiflaError(line: line, message: "'part' was told to take \(c) characters, but a count can't be less than 0." + suffix)
            }
            if let s = start, s > length {
                if length == 0 {
                    throw NiflaError(line: line, message: "'part' was told to start at character \(s), but the text has no characters yet." + suffix)
                }
                throw NiflaError(line: line, message: "'part' was told to start at character \(s), but the text has only \(length) characters, numbered 0 to \(length - 1)." + suffix)
            }
            if let s = start, let c = count, length > 0, s + c > length {
                throw NiflaError(line: line, message: "'part' was told to take \(c) characters starting at character \(s), but the text has only \(length) characters, numbered 0 to \(length - 1) — that runs past the end." + suffix)
            }
        default:
            return
        }
    }

    // The number an expression provably holds, from literals and
    // simple tracked facts only: a literal, the negative of one,
    // a variable whose constant is tracked, and plain arithmetic
    // over those. Anything else — a call, a field, an item —
    // proves nothing, and this stays silent (nil).
    private func constNumber(_ expr: Expr, in env: StaticEnv) -> Double? {
        switch expr {
        case .number(let value, _):
            return value
        case .negate(let inner, _):
            return constNumber(inner, in: env).map { -$0 }
        case .variable(let name, _):
            return env.lookupConstant(name)
        case .binary(let left, let op, let right, _):
            guard let a = constNumber(left, in: env), let b = constNumber(right, in: env) else { return nil }
            switch op {
            case "+": return a + b
            case "-": return a - b
            case "*": return a * b
            case "/": return b == 0 ? nil : a / b
            default: return nil
            }
        default:
            return nil
        }
    }

    // The length an expression provably holds, when it is a
    // literal list or text: the length is on its face. (A
    // variable's length is never taken from another variable —
    // the two names share one list, and either could change it
    // where the checker can't watch.)
    private func literalLength(of expr: Expr) -> Int? {
        switch expr {
        case .list(let items, _): return items.count
        case .text(let text, _): return text.count
        default: return nil
        }
    }

    // Whether an expression provably holds an empty list: the
    // empty list itself, or a variable tracked as holding one.
    private func isEmptyListExpr(_ expr: Expr, in env: StaticEnv) -> Bool {
        switch expr {
        case .list(let items, _):
            return items.isEmpty
        case .variable(let name, _):
            return env.isProvenEmpty(name)
        default:
            return false
        }
    }

    // A list value handed on — into a new variable, by a 'let'
    // or a set — is the same list under two names, and the new
    // name could grow it where the checker can't watch. The old
    // name's facts are given up, so the checker stays honest.
    private func noteAliasing(of expr: Expr, env: inout StaticEnv) {
        if case .variable(let name, _) = expr {
            env.forgetFacts(about: name)
        }
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
        // Stone 19: the empty value, and values that may be it.
        // Equality is how a maybe is checked, so '==' and '!='
        // are always allowed. Text joining is the other safe
        // road: '+' with text on either side joins anything,
        // the empty value by its name, as the run does. Every
        // other use of a proven nothing is refused in the run's
        // own words; every other use of a maybe is refused as
        // an unhandled maybe — the nothing road is not taken
        // care of there.
        if op != "==" && op != "!=" {
            let leftMaybe = isMaybe(left), rightMaybe = isMaybe(right)
            if leftMaybe || rightMaybe {
                if op == "+" && (left == .text || right == .text) {
                    return .text
                }
                throw unhandledMaybeError(kind: leftMaybe ? left : right, line: line)
            }
            if left == .nothing || right == .nothing {
                if op == "+" && (left == .text || right == .text) {
                    return .text
                }
                let note = " Nothing is the empty value: there is nothing there to work with. If a value might be nothing, check it first — if value == nothing { ... } else { ... } — and use it in the 'else', where it is known to be there."
                switch op {
                case "+":
                    throw NiflaError(line: line, message: "I can't add \(left.phrase) and \(right.phrase). '+' adds two numbers, or joins text together.\(note) I caught this before the program ran, so nothing ran.")
                case "-", "*", "/":
                    let verb = op == "-" ? "subtract" : (op == "*" ? "multiply" : "divide")
                    throw NiflaError(line: line, message: "I can't \(verb) \(left.phrase) and \(right.phrase). '\(op)' works on two numbers. (Only '+' joins text.)\(note) I caught this before the program ran, so nothing ran.")
                case "<", "<=", ">", ">=":
                    throw NiflaError(line: line, message: "I can't compare \(left.phrase) and \(right.phrase) with '\(op)'. '\(op)' compares two numbers. (Text and true/false values can be checked with == and !=.)\(note) I caught this before the program ran, so nothing ran.")
                default:
                    break
                }
            }
        }
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
