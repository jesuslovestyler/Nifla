// Nifla — Stone 1 interpreter: the interpreter.
//
// Walks the parser's tree and runs it: values, variables in nested
// scopes (one per block), and the running of statements. All problems
// are reported as plain-words NiflaErrors with a line number.

import Foundation

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

    // Takes a field out (Stone 10): hands back the value it held,
    // or nil when the object has no such field.
    func remove(_ name: String) -> Value? {
        guard let value = values[name] else { return nil }
        values[name] = nil
        fieldNames.removeAll { $0 == name }
        return value
    }
}

// A list (Stone 6): values in order, held in a class on purpose —
// lists are shared by reference, the way objects are. Two variables
// that hold the same list see each other's appends and item changes.
final class NiflaList {
    var items: [Value] = []

    init(items: [Value] = []) {
        self.items = items
    }
}

// A block of bytes (Stone 9): raw memory, a fixed number of bytes,
// each a whole number from 0 to 255. It is a class on purpose — a
// bytes block is shared by reference, the way objects and lists
// are, so a floor block handed the block works on the very memory
// the high-level side reads back afterwards. Its size is set when
// it is made and never changes; its bytes can be read and written
// by number, the way a list's items can.
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
    // Stone 19: the empty value — what 'nothing' stands for, and
    // what a 'maybe' variable holds when it holds nothing. It is
    // a real value (it can be held, handed over, and compared
    // with ==), but no work can be done on it: the operations
    // refuse it in plain words, and the checker refuses the uses
    // it can prove before the program runs.
    case nothing

    // Whether this value is the empty value.
    var isNothing: Bool {
        if case .nothing = self { return true }
        return false
    }

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
        case .list(let list):
            let id = ObjectIdentifier(list)
            if seen.contains(id) { return "..." }
            if list.items.isEmpty { return "[]" }
            var inner = seen
            inner.insert(id)
            let parts = list.items.map { $0.render(seen: inner, quoted: true) }
            return "[" + parts.joined(separator: ", ") + "]"
        case .bytes(let bytes):
            // A block of bytes is shown as its numbers, in a shape
            // no list can be mistaken for: bytes(72, 101, 108).
            let parts = bytes.data.map { String($0) }
            return "bytes(" + parts.joined(separator: ", ") + ")"
        case .nothing:
            return "nothing"
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
        case .nothing:
            return "nothing"
        }
    }
}

// One scope of variables. Blocks get their own scope, linked to the
// scope around them; a variable made inside a block stays inside it.
final class Scope {
    private var values: [String: Value] = [:]
    // Stone 18: the kind annotation a variable in this scope was
    // made with, if any — the runtime guard's memory of the
    // promise, consulted whenever the variable is set.
    private var annotations: [String: String] = [:]
    private let parent: Scope?

    init(parent: Scope? = nil) {
        self.parent = parent
    }

    func lookup(_ name: String) -> Value? {
        values[name] ?? parent?.lookup(name)
    }

    func declareAnnotation(_ name: String, _ kindWord: String) {
        annotations[name] = kindWord
    }

    func annotation(for name: String) -> String? {
        annotations[name] ?? parent?.annotation(for: name)
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
    // Stone 18: the annotations on the 'make' line — a kind word
    // per parameter (nil where there is none) and the promised
    // kind after the arrow, if any.
    let paramKinds: [String?]
    let returnKind: String?
    let body: [Stmt]
    let home: Scope
}

// How a 'give' line hands its value back: it is thrown like an error
// and caught by the call that is running the function. It never
// reaches the person writing Nifla.
private struct ReturnSignal: Error {
    let value: Value
    let line: Int
}

// Stone 18: the kind word a value answers to — the annotation
// vocabulary (see the parser), used by the runtime guards.
func valueKindWord(_ value: Value) -> String {
    switch value {
    case .number: return "number"
    case .text: return "text"
    case .boolean: return "boolean"
    case .object: return "object"
    case .list: return "list"
    case .bytes: return "bytes"
    case .nothing: return "nothing"
    }
}

// Whether a value (or the lack of one, from a function that
// gave nothing back) satisfies an annotation.
func kindSatisfies(_ kindWord: String, _ value: Value?) -> Bool {
    // Stone 19: 'nothing' is a value now — the empty value
    // satisfies a 'nothing' mark, and so does a function that
    // gave nothing back at all (the two are the same absence,
    // seen from the two sides of a call).
    if kindWord == "nothing" {
        guard let value else { return true }
        return value.isNothing
    }
    // Stone 19: a 'maybe' mark is satisfied by the kind it
    // names, by the empty value, and by a function that gave
    // nothing back.
    if kindWord.hasPrefix("maybe ") {
        guard let value else { return true }
        if value.isNothing { return true }
        return valueKindWord(value) == String(kindWord.dropFirst("maybe ".count))
    }
    guard let value else { return false }
    return valueKindWord(value) == kindWord
}

// Stone 19: the words that follow an operation's refusal when
// one side was the empty value — why it failed, and the shape
// that works. The checker speaks the same words (before the
// run, with its own closing line added), and the compiled
// runtime carries the same text.
let nothingNote = " Nothing is the empty value: there is nothing there to work with. If a value might be nothing, check it first — if value == nothing { ... } else { ... } — and use it in the 'else', where it is known to be there."

// A built-in tool (Stone 6): a function every Nifla program has
// from the start, without making it. `params` names the values it
// takes, for plain-words messages; `example` shows a call to it.
struct BuiltinDef {
    let params: [String]
    let example: String
}

// The built-in tools, in one place so the interpreter, the
// compiled programs' runtime, and the checker all agree on their
// names and how many values they take.
let builtinTools: [String: BuiltinDef] = [
    "length": BuiltinDef(params: ["value"], example: "length(\"Tyler\")"),
    "join": BuiltinDef(params: ["list", "separator"], example: "join(words, \" \")"),
    "split": BuiltinDef(params: ["text", "separator"], example: "split(\"a,b\", \",\")"),
    "part": BuiltinDef(params: ["text", "start", "count"], example: "part(\"Tyler\", 0, 2)"),
    "find": BuiltinDef(params: ["text", "piece"], example: "find(\"Tyler\", \"y\")"),
    "append": BuiltinDef(params: ["list", "value"], example: "append(items, 4)"),
    "readfile": BuiltinDef(params: ["path"], example: "readfile(\"notes.txt\")"),
    "readbytes": BuiltinDef(params: ["path"], example: "readbytes(\"notes.txt\")"),
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
    "asnumber": BuiltinDef(params: ["text"], example: "asnumber(\"620\")"),
    "bitand": BuiltinDef(params: ["first", "second"], example: "bitand(12, 10)"),
    "bitor": BuiltinDef(params: ["first", "second"], example: "bitor(12, 10)"),
    "bitxor": BuiltinDef(params: ["first", "second"], example: "bitxor(12, 10)"),
    "astext": BuiltinDef(params: ["bytes"], example: "astext(block)"),
    "wholediv": BuiltinDef(params: ["first", "second"], example: "wholediv(17, 5)"),
    "leftover": BuiltinDef(params: ["first", "second"], example: "leftover(17, 5)"),
    "rounddown": BuiltinDef(params: ["value"], example: "rounddown(3.5)"),
    "roundup": BuiltinDef(params: ["value"], example: "roundup(3.5)"),
    "absolute": BuiltinDef(params: ["value"], example: "absolute(-7)"),
]

// The plain-words message for a call to a built-in tool with the
// wrong number of values — the same shape as the one for functions
// a program makes itself.
func builtinCountMessage(name: String, def: BuiltinDef, given: Int) -> String {
    let takes: String
    switch def.params.count {
    case 0: takes = "no values"
    case 1: takes = "1 value (\(def.params[0]))"
    default: takes = "\(def.params.count) values (\(def.params.joined(separator: ", ")))"
    }
    return "The tool '\(name)' takes \(takes), but it was given \(given). Call it like: \(def.example)."
}

// Stone 26: reading a number out of text, the 'asnumber'
// tool's work. The accepted writing is plain: a '-' first
// when the number is below zero, then digits, then — if a
// fraction is wanted — one '.' and more digits. Nothing
// else: no spaces, no '+', no exponent letters. The value
// is built digit by digit in the language's own numbers,
// the same steps in every mirror, so every door reads the
// same text to the same number. Text that isn't written
// that way, and a number too big for the language's
// numbers to hold, come back as nil — the tool turns that
// into a problem 'attempt' can catch.
func readNumberText(_ text: String) -> Double? {
    // A character counts as a digit only when it is exactly
    // one of the ten plain digit characters — one scalar,
    // nothing riding on it.
    func digit(_ ch: Character) -> Double? {
        guard ch.unicodeScalars.count == 1, let scalar = ch.unicodeScalars.first,
              scalar.value >= 48, scalar.value <= 57 else { return nil }
        return Double(scalar.value - 48)
    }
    let chars = Array(text)
    var i = 0
    var negative = false
    if i < chars.count && chars[i] == "-" {
        negative = true
        i += 1
    }
    var whole = 0.0
    var wholeDigits = 0
    while i < chars.count, let d = digit(chars[i]) {
        whole = whole * 10 + d
        wholeDigits += 1
        i += 1
    }
    guard wholeDigits > 0 else { return nil }
    var value = whole
    if i < chars.count && chars[i] == "." {
        i += 1
        var fraction = 0.0
        var scale = 1.0
        var fractionDigits = 0
        while i < chars.count, let d = digit(chars[i]) {
            fraction = fraction * 10 + d
            scale *= 10
            fractionDigits += 1
            i += 1
        }
        guard fractionDigits > 0 else { return nil }
        value = whole + fraction / scale
    }
    guard i == chars.count else { return nil }
    let signed = negative ? -value : value
    guard signed.isFinite else { return nil }
    return signed == 0 ? 0 : signed
}

// Stone 27: working with bits, the 'bitand', 'bitor', and
// 'bitxor' tools' shared work. A bit tool can only count
// the bits of a whole number from zero up, no bigger than
// the language's numbers hold exactly — 2^53, the reach
// the feather reckoning already trusts. Anything else is
// a problem 'attempt' can catch, said in plain words:
// a fraction has no bits to count, bits below zero have
// no plain counting, and past the exact reach the bits
// could not be counted honestly.
func bitToolNumber(_ value: Value, tool: String, line: Int) throws -> Double {
    guard case .number(let number) = value else {
        throw NiflaError(line: line, message: "'\(tool)' needs a whole number to work on, but it was given \(value.described).")
    }
    if number != number.rounded() {
        throw NiflaError(line: line, message: "'\(tool)' works on whole numbers — bits are counted in whole numbers — but it was given \(formatNumber(number)). Use a whole number, like \(formatNumber(number.rounded(.down))) or \(formatNumber(number.rounded(.up))).")
    }
    if number < 0 {
        throw NiflaError(line: line, message: "'\(tool)' works on whole numbers from zero up — bits below zero have no plain counting — but it was given \(formatNumber(number)).")
    }
    if number > 9007199254740992 {
        throw NiflaError(line: line, message: "'\(tool)' works on whole numbers up to 9007199254740992, as far as the language's numbers stay exact, but it was given a bigger one.")
    }
    return number
}

// The bits themselves, counted the same way in every
// mirror: place by place from the ones place up, each
// number halved as its bit is read — the very steps the
// self-made feather checker's 'xorbyte' walks by hand.
// 'keep' says whether a place stands in the answer,
// given the two numbers' bits at that place.
func combineBits(_ a: Double, _ b: Double, _ keep: (Bool, Bool) -> Bool) -> Double {
    var x = a
    var y = b
    var place = 1.0
    var out = 0.0
    while x > 0 || y > 0 {
        let xBit = x.truncatingRemainder(dividingBy: 2)
        let yBit = y.truncatingRemainder(dividingBy: 2)
        if keep(xBit == 1, yBit == 1) {
            out += place
        }
        x = (x - xBit) / 2
        y = (y - yBit) / 2
        place *= 2
    }
    return out
}

// Stone 30: dividing into whole numbers, the 'wholediv'
// tool's work. '/' gives the true quotient with its
// fraction; 'wholediv' gives the whole part alone, the
// fraction dropped toward zero — the way Swift's whole
// numbers divide, so wholediv(-7, 2) is -3. The numbers
// handed to it must themselves be whole, no bigger in
// size than the language's numbers hold exactly — 2^53,
// the reach the feather reckoning already trusts. A
// fraction, or a bigger one, is a problem 'attempt' can
// catch, said in plain words; dividing by zero is the
// same problem '/' raises, in the same words.
func wholeDivNumber(_ value: Value, tool: String, role: String, line: Int) throws -> Double {
    guard case .number(let number) = value else {
        throw NiflaError(line: line, message: "'\(tool)' needs \(role), but it was given \(value.described).")
    }
    if number != number.rounded() {
        throw NiflaError(line: line, message: "'\(tool)' works on whole numbers — it is the dividing that drops the fraction, not the numbers handed to it — but it was given \(formatNumber(number)). Use a whole number, like \(formatNumber(number.rounded(.down))) or \(formatNumber(number.rounded(.up))).")
    }
    if number > 9007199254740992 || number < -9007199254740992 {
        throw NiflaError(line: line, message: "'\(tool)' works on whole numbers up to 9007199254740992 in size, as far as the language's numbers stay exact, but it was given a bigger one.")
    }
    return number
}

// The quotient itself, counted the same way in every
// mirror: by doubling chunks of the divisor, the way a
// person divides on paper — take the biggest doubled
// chunk that still fits, take it away, and count how
// many it stood for — so every step is whole-number
// work the language's numbers hold exactly, and no
// mirror's own division can round the answer its own
// way. 'a' is the size of the number divided (zero or
// more) and 'b' the size of the number it is divided
// by (one or more); the sign is the caller's to restore.
func wholeQuotient(_ a: Double, _ b: Double) -> Double {
    var rest = a
    var quotient = 0.0
    while rest >= b {
        var chunk = b
        var count = 1.0
        while chunk + chunk <= rest {
            chunk += chunk
            count += count
        }
        rest -= chunk
        quotient += count
    }
    return quotient
}

// Stone 31: what a dividing leaves, the 'leftover'
// tool's work — the rest of the divided number after
// the divisor has been taken out of it 'wholediv'
// times. It is counted by the same doubling steps as
// the quotient: what remains when the last chunk is
// taken away. The sign is the divided number's, the
// way Swift's whole numbers leave it, so the two
// always add back up: wholediv(n, d) * d + leftover
// (n, d) is n. Until this stone the leftover was
// counted in the open, as n - wholediv(n, d) * d.
func wholeRest(_ a: Double, _ b: Double) -> Double {
    var rest = a
    while rest >= b {
        var chunk = b
        while chunk + chunk <= rest {
            chunk += chunk
        }
        rest -= chunk
    }
    return rest
}

// The interpreter's refusal of floor code (Stone 7), in one place
// so the entry point's scan and the block itself say the same words.
let floorRefusalMessage = "This is floor code — raw instructions for the processor — and the interpreter can't run it. Floor code runs only in a compiled program: build this program with niflac and run the program it makes."

// Finds the first floor block in a program, wherever it is nested —
// inside a branch, a loop, or a function — and gives back its line.
// The interpreter refuses a program that holds floor code before
// anything runs, even floor code on a path the run wouldn't take:
// the interpreter can't run it at all.
func firstFloorLine(in statements: [Stmt]) -> Int? {
    for statement in statements {
        switch statement {
        case .declare(_, _, let value, _), .assign(_, let value, _):
            if let line = firstFloorLine(in: value) { return line }
        case .say(let value, _), .give(let value, _):
            if let line = firstFloorLine(in: value) { return line }
        case .assignTarget(let target, let value, _):
            if let line = firstFloorLine(in: target) { return line }
            if let line = firstFloorLine(in: value) { return line }
        case .ifElse(let condition, let then, let otherwise, _):
            if let line = firstFloorLine(in: condition) { return line }
            if let line = firstFloorLine(in: then) { return line }
            if let otherwise, let line = firstFloorLine(in: otherwise) { return line }
        case .whileLoop(let condition, let body, _):
            if let line = firstFloorLine(in: condition) { return line }
            if let line = firstFloorLine(in: body) { return line }
        case .repeatLoop(let count, let body, _):
            if let line = firstFloorLine(in: count) { return line }
            if let line = firstFloorLine(in: body) { return line }
        case .forEach(_, let over, let body, _):
            if let line = firstFloorLine(in: over) { return line }
            if let line = firstFloorLine(in: body) { return line }
        case .define(_, _, _, _, let body, _):
            if let line = firstFloorLine(in: body) { return line }
        case .attempt(let body, let recovery, _):
            if let line = firstFloorLine(in: body) { return line }
            if let line = firstFloorLine(in: recovery) { return line }
        case .doCall(_, let args, _):
            for arg in args {
                if let line = firstFloorLine(in: arg) { return line }
            }
        case .doExpr(let expr, _):
            if let line = firstFloorLine(in: expr) { return line }
        }
    }
    return nil
}

func firstFloorLine(in expr: Expr) -> Int? {
    switch expr {
    case .nothing:
        return nil
    case .floor(_, _, let line):
        // The block's own line is where the floor construct starts;
        // a program holding any floor block is refused at the
        // first one, so there is no need to look inside its values.
        return line
    case .call(_, let args, _):
        for arg in args {
            if let line = firstFloorLine(in: arg) { return line }
        }
        return nil
    case .object(let fields, _):
        for field in fields {
            if let line = firstFloorLine(in: field.value) { return line }
        }
        return nil
    case .list(let items, _):
        for item in items {
            if let line = firstFloorLine(in: item) { return line }
        }
        return nil
    case .field(let base, _, _):
        return firstFloorLine(in: base)
    case .negate(let inner, _):
        return firstFloorLine(in: inner)
    case .index(let base, let index, _):
        if let line = firstFloorLine(in: base) { return line }
        return firstFloorLine(in: index)
    case .binary(let left, _, let right, _):
        if let line = firstFloorLine(in: left) { return line }
        return firstFloorLine(in: right)
    case .number, .text, .boolean, .variable:
        return nil
    }
}

final class Interpreter {
    // The runaway guard (Stone 2, re-counted by Stone 33): a kindness
    // limit of a million passes on ONE loop's run — each time a loop
    // starts, it is given a fresh count of its own, kept on this stack
    // (a loop inside another keeps its own count under the outer
    // loop's). A loop that would spin forever is stopped with a
    // plain-words error instead of hanging; a program of many loops,
    // each finishing, may pass a million times in all and run on —
    // a forever-running program of finishing loops (an operating
    // system's main loop, say) is not a runaway.
    private var loopBudgets: [Int] = []
    private let loopPassLimit = 1_000_000

    // The words handed to the program when it was started, after
    // the program's own file name — what arguments() gives (Stone 6).
    var programArguments: [String] = []

    // The functions this run has made, by name (Stone 3).
    private var functions: [String: FunctionDef] = [:]

    // The call-depth guard (Stone 3): how many calls are running at
    // once, one inside another. A function that calls itself without a
    // way to stop is caught by this limit and stopped with a
    // plain-words error instead of crashing.
    private var callDepth = 0
    private let callDepthLimit = 500

    private func tickLoop(line: Int) throws {
        if loopBudgets.isEmpty { loopBudgets.append(0) }
        loopBudgets[loopBudgets.count - 1] += 1
        if loopBudgets[loopBudgets.count - 1] > loopPassLimit {
            throw NiflaError(line: line, message: "This loop ran more than a million times and was stopped — it may never end. Check the condition, and make sure something inside the loop changes each time around, so it can finish.")
        }
    }

    // Runs one loop's whole run under a fresh pass budget of its
    // own (Stone 33): the budget is laid down as the loop starts
    // and lifted however the loop ends — finished, stopped by a
    // problem, or left by a 'give' travelling out of it.
    private func withLoopBudget<T>(_ body: () throws -> T) throws -> T {
        loopBudgets.append(0)
        defer { loopBudgets.removeLast() }
        return try body()
    }

    func run(_ program: [Stmt]) throws {
        let top = Scope()
        for statement in program {
            try execute(statement, in: top)
        }
    }

    private func execute(_ statement: Stmt, in scope: Scope) throws {
        switch statement {
        case .declare(let name, let kindWord, let valueExpr, let line):
            if scope.isDeclaredHere(name) {
                throw NiflaError(line: line, message: "There is already a variable called '\(name)' in this block. To change what it holds, write: \(name) = ...")
            }
            let value = try evaluate(valueExpr, in: scope)
            if let kindWord {
                try checkVariableGuard(name: name, kindWord: kindWord, value: value, line: line)
                scope.declare(name, value)
                scope.declareAnnotation(name, kindWord)
            } else {
                scope.declare(name, value)
            }

        case .assign(let name, let valueExpr, let line):
            let value = try evaluate(valueExpr, in: scope)
            if let kindWord = scope.annotation(for: name) {
                try checkVariableGuard(name: name, kindWord: kindWord, value: value, line: line)
            }
            if !scope.assign(name, value) {
                throw NiflaError(line: line, message: "I can't set '\(name)', because no variable called '\(name)' has been made yet. Make one first with: let \(name) = ...")
            }

        case .assignTarget(let target, let valueExpr, let line):
            // The target is a chain of steps; every step but the
            // last is read, to reach the object or list whose field
            // or item is being set, and the last step names it.
            // Setting a field that isn't there yet adds it.
            try assignTo(target, valueExpr: valueExpr, line: line, in: scope)

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
            try withLoopBudget {
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
            try withLoopBudget {
                while done < count {
                    try tickLoop(line: line)
                    let child = Scope(parent: scope)
                    for inner in body {
                        try execute(inner, in: child)
                    }
                    done += 1
                }
            }

        case .forEach(let name, let overExpr, let body, let line):
            // The list (or text) is read once, as it stands when the
            // loop begins, and the block runs once for each item in
            // it, with the item under the loop's name. Each pass runs
            // in a fresh block scope, the same way the other loops do.
            let over = try evaluate(overExpr, in: scope)
            let items: [Value]
            switch over {
            case .list(let list):
                items = list.items
            case .text(let text):
                items = Array(text).map { Value.text(String($0)) }
            case .bytes(let bytes):
                items = bytes.data.map { Value.number(Double($0)) }
            default:
                throw NiflaError(line: line, message: "'for' needs a list, some text, or a block of bytes to walk through, but here it was given \(over.described). Write it like: for item in items { ... }")
            }
            try withLoopBudget {
                for item in items {
                    try tickLoop(line: line)
                    let child = Scope(parent: scope)
                    child.declare(name, item)
                    for inner in body {
                        try execute(inner, in: child)
                    }
                }
            }

        case .define(let name, let params, let paramKinds, let returnKind, let body, let line):
            // Making a function is a line like any other: it runs when
            // the program reaches it, so a function is ready to call
            // from that line on.
            if builtinTools[name] != nil {
                throw NiflaError(line: line, message: "There is already a built-in tool called '\(name)' — every Nifla program has it from the start. A function can't be made with that name; rename the function.")
            }
            if functions[name] != nil {
                throw NiflaError(line: line, message: "There is already a function called '\(name)'. Each function needs its own name — rename this one, or take out the earlier 'make \(name)'.")
            }
            functions[name] = FunctionDef(params: params, paramKinds: paramKinds, returnKind: returnKind, body: body, home: scope)

        case .give(let valueExpr, let line):
            guard callDepth > 0 else {
                throw NiflaError(line: line, message: "'give' hands a value back from a function to whoever called it, but this line is not inside a function. To show a value here, use 'say' instead.")
            }
            throw ReturnSignal(value: try evaluate(valueExpr, in: scope), line: line)

        case .attempt(let body, let recovery, _):
            // Try the first block; if anything in it goes wrong —
            // any plain-words problem, however deep inside it —
            // run the second block instead, with the problem's
            // words held in a variable called 'problem'. A 'give'
            // in either block is not a problem: it hands its value
            // back as always, straight through the attempt.
            do {
                let child = Scope(parent: scope)
                for inner in body {
                    try execute(inner, in: child)
                }
            } catch let error as NiflaError {
                let child = Scope(parent: scope)
                child.declare("problem", .text(error.message))
                for inner in recovery {
                    try execute(inner, in: child)
                }
            }

        case .doCall(let name, let args, let line):
            // A call on its own line: run it for what it does. Any
            // value it gives back is simply not used.
            _ = try callFunction(name: name, argExprs: args, line: line, in: scope)

        case .doExpr(let expr, _):
            // An expression run for what it does — a floor block
            // standing on its own (Stone 7). Its value goes unused.
            _ = try evaluate(expr, in: scope)
        }
    }

    // Sets the field or item a target chain names. The chain's
    // base is read (which reads every step before the last), the
    // holder the last step names is checked, and only then is the
    // new value worked out — the order the interpreter has always
    // used for field-setting lines.
    private func assignTo(_ target: Expr, valueExpr: Expr, line: Int, in scope: Scope) throws {
        switch target {
        case .field(let baseExpr, let fieldName, _):
            let base = try evaluate(baseExpr, in: scope)
            guard case .object(let object) = base else {
                throw NiflaError(line: line, message: "I can't set the field '\(fieldName)' on \(base.described), because only an object has fields. Make an object first, like: let person = { name: \"Tyler\" } — then person.\(fieldName) = ... works.")
            }
            object.set(fieldName, try evaluate(valueExpr, in: scope))

        case .index(let baseExpr, let indexExpr, let indexLine):
            let base = try evaluate(baseExpr, in: scope)
            switch base {
            case .list(let list):
                let index = try itemNumber(try evaluate(indexExpr, in: scope), line: indexLine)
                if list.items.isEmpty {
                    throw NiflaError(line: indexLine, message: "This list has no items yet, so there is no item \(index) to set. To add an item at the end, use append — like: append(items, ...).")
                }
                guard index >= 0 && index < list.items.count else {
                    throw NiflaError(line: indexLine, message: "This list has \(list.items.count) items, numbered 0 to \(list.items.count - 1), so there is no item \(index) to set. To add an item at the end, use append — like: append(items, ...).")
                }
                list.items[index] = try evaluate(valueExpr, in: scope)
            case .bytes(let bytes):
                let index = try itemNumber(try evaluate(indexExpr, in: scope), line: indexLine)
                if bytes.data.isEmpty {
                    throw NiflaError(line: indexLine, message: "This block of bytes has no bytes yet, so there is no byte \(index) to set. Make a bigger block with makebytes — like: makebytes(8).")
                }
                guard index >= 0 && index < bytes.data.count else {
                    throw NiflaError(line: indexLine, message: "This block of bytes has \(bytes.data.count) bytes, numbered 0 to \(bytes.data.count - 1), so there is no byte \(index) to set.")
                }
                bytes.data[index] = try byteValue(try evaluate(valueExpr, in: scope), line: indexLine)
            case .text:
                throw NiflaError(line: indexLine, message: "I can't change one character of some text — once text is made, it doesn't change. To change it, build the new text and set the variable to it instead.")
            default:
                throw NiflaError(line: indexLine, message: "I can only set an item in a list, like: items[0] = 30 — but this is \(base.described), which has no items to set.")
            }

        default:
            throw NiflaError(line: line, message: "I can only set a field on an object or an item in a list, like: person.years = 30 or items[0] = 30.")
        }
    }

    // Checks that a value can be stored in a block of bytes
    // (Stone 9): a whole number from 0 to 255.
    private func byteValue(_ value: Value, line: Int) throws -> UInt8 {
        guard case .number(let number) = value, number == number.rounded(), number >= 0, number <= 255 else {
            throw NiflaError(line: line, message: "A byte is a whole number from 0 to 255, but I was given \(value.described).")
        }
        return UInt8(number)
    }

    // Checks that a value can pick an item: a whole number. The
    // range check belongs to the reading or setting, which knows
    // how many items there are.
    private func itemNumber(_ value: Value, line: Int) throws -> Int {
        guard case .number(let number) = value else {
            throw NiflaError(line: line, message: "I can't use \(value.described) to pick an item. Items are picked by a whole number — 0 for the first one, 1 for the second, and so on.")
        }
        guard number == number.rounded() && abs(number) < 1e15 else {
            throw NiflaError(line: line, message: "An item number must be a whole number, but I was given \(formatNumber(number)). Use a whole number, like 0, 1, or 2.")
        }
        return Int(number)
    }

    // Reads one item of a list, or one character of some text.
    private func readIndex(_ base: Value, _ indexValue: Value, line: Int) throws -> Value {
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

    // Runs one call: a built-in tool first (every program has
    // them), then a function the program made — checking it exists
    // and was given the right number of values, then running its
    // body in a fresh scope inside its home, with the parameters
    // declared there. Returns the value the call gave back, or nil
    // when a made function finished without a 'give'.
    private func callFunction(name: String, argExprs: [Expr], line: Int, in scope: Scope) throws -> Value? {
        if let builtin = builtinTools[name] {
            let args = try argExprs.map { try evaluate($0, in: scope) }
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
        let args = try argExprs.map { try evaluate($0, in: scope) }
        guard args.count == def.params.count else {
            throw NiflaError(line: line, message: "The function '\(name)' takes \(takesText(def.params)), but it was given \(args.count). Make the call match how the function was made: \(name)(\(def.params.joined(separator: ", "))).")
        }
        // Stone 18: the guards at the annotated boundaries of
        // the call — each annotated parameter checks the value
        // handed to it, here at the call.
        for (index, param) in def.params.enumerated() {
            if index < def.paramKinds.count, let kindWord = def.paramKinds[index], !kindSatisfies(kindWord, args[index]) {
                throw NiflaError(line: line, message: "The value handed to '\(name)' for '\(param)' is \(args[index].described), but '\(param)' is marked as \(StaticKind.phrase(forKindWord: kindWord)) by its annotation. Change what the call hands over, or change the annotation.")
            }
        }
        guard callDepth < callDepthLimit else {
            throw NiflaError(line: line, message: "This call is more than five hundred functions deep and was stopped — it may never finish. A function that calls itself needs a way to stop, like an 'if' that gives an answer for the smallest case instead of calling again.")
        }
        callDepth += 1
        defer { callDepth -= 1 }
        let callScope = Scope(parent: def.home)
        for (index, param) in def.params.enumerated() {
            callScope.declare(param, args[index])
            if index < def.paramKinds.count, let kindWord = def.paramKinds[index] {
                callScope.declareAnnotation(param, kindWord)
            }
        }
        do {
            for inner in def.body {
                try execute(inner, in: callScope)
            }
        } catch let signal as ReturnSignal {
            if let returnKind = def.returnKind, !kindSatisfies(returnKind, signal.value) {
                throw NiflaError(line: signal.line, message: "'\(name)' is marked to give back \(StaticKind.phrase(forKindWord: returnKind)) by its annotation, but this 'give' hands back \(signal.value.described). Change the value, or change the annotation.")
            }
            // Stone 19: a function marked '-> nothing' never
            // hands a value back — a 'give nothing' line inside
            // it is an early way out, and the empty value it
            // names is absorbed by the promise.
            if def.returnKind == "nothing" {
                return nil
            }
            return signal.value
        }
        if let returnKind = def.returnKind {
            // Stone 19: a function marked 'maybe' that finishes
            // without a 'give' hands back the empty value —
            // that is exactly what the mark says may happen.
            if returnKind.hasPrefix("maybe ") {
                return .nothing
            }
            if returnKind != "nothing" {
                throw NiflaError(line: line, message: "'\(name)' is marked to give back \(StaticKind.phrase(forKindWord: returnKind)) by its annotation, but it finished without giving a value back. Add a 'give' line inside '\(name)', or change the annotation.")
            }
        }
        return nil
    }

    // Stone 18: the runtime guard on a variable with an
    // annotation — its 'let' line, and every later setting of
    // it, must hand it a value of the marked kind.
    private func checkVariableGuard(name: String, kindWord: String, value: Value, line: Int) throws {
        guard !kindSatisfies(kindWord, value) else { return }
        throw NiflaError(line: line, message: "'\(name)' is marked as \(StaticKind.phrase(forKindWord: kindWord)) by its annotation, but this value is \(value.described). Change the value, or change the annotation.")
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
        for candidate in Array(functions.keys) + Array(builtinTools.keys) where candidate != name {
            let distance = editDistance(name, candidate)
            if distance <= 2 && (best == nil || distance < best!.distance) {
                best = (candidate, distance)
            }
        }
        return best?.name
    }

    // Runs a built-in tool (Stone 6) on values already worked out,
    // checking each value's kind in plain words. Every tool gives a
    // value back.
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

        case "readbytes":
            // Stone 25: a file read as the bytes it is, not
            // as text — the reader the feather checker is
            // written with, since a feather's program bytes
            // are not text and 'readfile' honestly refuses
            // them. The block holds the file's bytes whole,
            // under the same 16 MiB cap as 'makebytes'.
            guard case .text(let path) = args[0] else {
                throw NiflaError(line: line, message: "'readbytes' needs the name of a file, as text, but it was given \(args[0].described).")
            }
            let data: Data
            do {
                data = try Data(contentsOf: URL(fileURLWithPath: path))
            } catch {
                throw NiflaError(line: line, message: "I couldn't read the file '\(path)'. Check the name and the folder, and try again.")
            }
            guard data.count <= 16_777_216 else {
                throw NiflaError(line: line, message: "'readbytes' read the file '\(path)', but it holds \(data.count) bytes, and one block can hold at most 16777216 bytes.")
            }
            let block = NiflaBytes(count: data.count)
            block.data = [UInt8](data)
            return .bytes(block)

        case "asnumber":
            // Stone 26: a number read out of text — the
            // toolbox's answer to the one honest gap the
            // Tutorial names. Text that isn't a number
            // written plainly is a problem, and 'attempt'
            // can catch it, like a file that isn't there.
            guard case .text(let text) = args[0] else {
                throw NiflaError(line: line, message: "'asnumber' needs some text to read a number from, but it was given \(args[0].described).")
            }
            guard let value = readNumberText(text) else {
                throw NiflaError(line: line, message: "'\(text)' is not a number 'asnumber' can read. A number is written with digits, a '-' first when it is below zero, and at most one '.' with digits after it — like 620 or -3.5.")
            }
            return .number(value)

        case "bitand", "bitor", "bitxor":
            // Stone 27: the bit tools — a bit stands in
            // the answer when it stands in both numbers
            // (bitand), in either one (bitor), or in one
            // but not the other (bitxor). The work the
            // self-made feather checker does by hand in
            // its 'xorbyte', given single words at last.
            let first = try bitToolNumber(args[0], tool: name, line: line)
            let second = try bitToolNumber(args[1], tool: name, line: line)
            switch name {
            case "bitand":
                return .number(combineBits(first, second) { $0 && $1 })
            case "bitor":
                return .number(combineBits(first, second) { $0 || $1 })
            default:
                return .number(combineBits(first, second) { $0 != $1 })
            }

        case "astext":
            // Stone 28: the text of a block of bytes —
            // the road back from bytes to text. 'readfile'
            // reads a file as text and honestly refuses
            // bytes that are not text; 'readbytes' holds
            // any bytes whole, and until this stone no
            // word could speak them as text, so a tool
            // holding bytes (the feather checker over a
            // card) had to build its letters one by one
            // and drop whatever it could not build.
            // The bytes are read as UTF-8, the writing
            // text is kept in; a run of bytes that is not
            // a letter stands in the text as the
            // replacement mark, the way every reader
            // shows it — never dropped, never guessed at.
            guard case .bytes(let block) = args[0] else {
                throw NiflaError(line: line, message: "'astext' needs a block of bytes to read as text, but it was given \(args[0].described).")
            }
            return .text(String(decoding: block.data, as: UTF8.self))

        case "wholediv":
            // Stone 30: dividing into whole numbers —
            // the whole part of the quotient, the
            // fraction dropped toward zero. The work
            // the self-made feather checker does by
            // hand in its 'floordiv', given a single
            // word at last.
            let first = try wholeDivNumber(args[0], tool: name, role: "a whole number to divide", line: line)
            let second = try wholeDivNumber(args[1], tool: name, role: "a whole number to divide by", line: line)
            if second == 0 {
                throw NiflaError(line: line, message: "I can't divide by zero. Dividing needs a second number that isn't zero.")
            }
            let quotient = wholeQuotient(abs(first), abs(second))
            if quotient == 0 {
                return .number(0)
            }
            return .number((first < 0) != (second < 0) ? -quotient : quotient)

        case "leftover":
            // Stone 31: what a dividing leaves — the
            // rest of the divided number after the
            // divisor has been taken out of it
            // 'wholediv' times, carrying the divided
            // number's sign. Counted in the open until
            // this stone, as n - wholediv(n, d) * d —
            // the self-made feather checker counts it
            // so at every limb of its reckoning.
            let first = try wholeDivNumber(args[0], tool: name, role: "a whole number to divide", line: line)
            let second = try wholeDivNumber(args[1], tool: name, role: "a whole number to divide by", line: line)
            if second == 0 {
                throw NiflaError(line: line, message: "I can't divide by zero. Dividing needs a second number that isn't zero.")
            }
            let rest = wholeRest(abs(first), abs(second))
            if rest == 0 {
                return .number(0)
            }
            return .number(first < 0 ? -rest : rest)

        case "rounddown", "roundup":
            // Stone 32: rounding a number to a whole
            // number — the whole number at or below it
            // (rounddown) or at or above it (roundup).
            // Until this stone the language had no
            // rounding word at all: the whole-number
            // tools refuse fractions, and finding the
            // whole number at or below one meant
            // reading its spoken form apart — the
            // self-host does exactly that, by hand, to
            // speak its rounding messages. A whole
            // number comes back unchanged, and past the
            // exact reach every number is already
            // whole, so the rounding is honest at
            // every size the language holds.
            guard case .number(let number) = args[0] else {
                throw NiflaError(line: line, message: "'\(name)' needs a number to round, but it was given \(args[0].described).")
            }
            return .number(name == "rounddown" ? number.rounded(.down) : number.rounded(.up))

        case "absolute":
            // Stone 34: a number's size, never below
            // nothing — below-zero numbers come back
            // with the sign lifted off, the rest come
            // back as they are, fractions keeping
            // their fraction. The word was first built
            // by hand as 'absn' in the Cardnull OS
            // calculator feather — a bare-metal guest,
            // which is why this word stands on every
            // door at once, bare metal included.
            guard case .number(let number) = args[0] else {
                throw NiflaError(line: line, message: "'absolute' needs a number to take the size of, but it was given \(args[0].described).")
            }
            return .number(abs(number))

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
            // A program's second voice (Stone 10): the value's
            // spoken form, on the error channel, with a new line —
            // the way 'say' speaks to the screen. Gives back how
            // many characters it wrote, the newline counted, the
            // way writefile counts what it wrote.
            let spoken = args[0].spoken
            FileHandle.standardError.write(Data((spoken + "\n").utf8))
            return .number(Double(spoken.count + 1))

        case "exitwith":
            // Ends the program now, leaving the given number as
            // its parting word to the system (Stone 10). Anything
            // already said is flushed out first.
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
    // list's items — the list handed in is left as it was. Every
    // item must be the same kind: numbers sort smallest first,
    // text sorts in the order the machine's own letter order
    // gives (the plain a-to-z of the characters as they stand).
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

    // A whole-number check for the counting tools ('part'): the
    // value is already known to be a number; this checks it is a
    // whole one and hands it back as an Int.
    private func wholeCount(_ value: Value, what: String, line: Int) throws -> Int {
        guard case .number(let number) = value else {
            throw NiflaError(line: line, message: "\(what) must be a number, but I was given \(value.described).")
        }
        guard number == number.rounded() && abs(number) < 1e15 else {
            throw NiflaError(line: line, message: "\(what) must be a whole number, but I was given \(formatNumber(number)).")
        }
        return Int(number)
    }

    private func evaluate(_ expr: Expr, in scope: Scope) throws -> Value {
        switch expr {
        case .number(let value, _):
            return .number(value)
        case .text(let value, _):
            return .text(value)
        case .boolean(let value, _):
            return .boolean(value)
        case .nothing:
            return .nothing

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

        case .list(let itemExprs, _):
            let list = NiflaList()
            for itemExpr in itemExprs {
                list.items.append(try evaluate(itemExpr, in: scope))
            }
            return .list(list)

        case .index(let baseExpr, let indexExpr, let line):
            let base = try evaluate(baseExpr, in: scope)
            let indexValue = try evaluate(indexExpr, in: scope)
            return try readIndex(base, indexValue, line: line)

        case .floor(_, _, let line):
            // Floor code is raw processor instructions; only a
            // compiled program can run it. (The entry point refuses
            // a program holding floor code before anything runs;
            // this is the same refusal, at the block itself.)
            throw NiflaError(line: line, message: floorRefusalMessage)

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
            if left.isNothing || right.isNothing {
                throw NiflaError(line: line, message: "I can't add \(left.described) and \(right.described). '+' adds two numbers, or joins text together.\(nothingNote)")
            }
            throw NiflaError(line: line, message: "I can't add \(left.described) and \(right.described). '+' adds two numbers, or joins text together.")

        case "-", "*", "/":
            guard case .number(let a) = left, case .number(let b) = right else {
                let verb = op == "-" ? "subtract" : (op == "*" ? "multiply" : "divide")
                if left.isNothing || right.isNothing {
                    throw NiflaError(line: line, message: "I can't \(verb) \(left.described) and \(right.described). '\(op)' works on two numbers. (Only '+' joins text.)\(nothingNote)")
                }
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
            case (.list(let a), .list(let b)): equal = a === b  // the very same list, not just alike
            case (.bytes(let a), .bytes(let b)): equal = a === b  // the very same block, not just alike
            case (.nothing, .nothing): equal = true  // Stone 19: the empty value is equal to itself — that is how a maybe is checked
            default: equal = false  // different kinds are never equal
            }
            return .boolean(op == "==" ? equal : !equal)

        case "<", "<=", ">", ">=":
            guard case .number(let a) = left, case .number(let b) = right else {
                if left.isNothing || right.isNothing {
                    throw NiflaError(line: line, message: "I can't compare \(left.described) and \(right.described) with '\(op)'. '\(op)' compares two numbers. (Text and true/false values can be checked with == and !=.)\(nothingNote)")
                }
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
