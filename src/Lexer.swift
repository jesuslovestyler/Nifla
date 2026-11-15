// Nifla — Stone 1 interpreter: the lexer.
//
// Turns Nifla source text into a list of tokens, remembering which line
// each token came from so error messages can point at the right place.
//
// Part of Nifla, a public-domain programming language by Tyler Kovalevich.
// See the Unlicense in the LICENSE file at the root of this repository.

// An error in plain words. Every problem Nifla finds in a program is
// reported this way: the line, what went wrong, and how to fix it.
// No stack traces ever reach the person writing Nifla.
struct NiflaError: Error {
    let line: Int
    let message: String
    var spoken: String { "Line \(line): \(message)" }
}

struct Token {
    enum Kind {
        case number(Double)
        case text(String)
        case name(String)
        case keyword(String)  // let, say, if, else, while, repeat, for, in, make, give, true, false, floor, attempt
        case symbol(String)   // +  -  *  /  (  )  {  }  [  ]  ,  .  :  =  ==  !=  <  <=  >  >=
        case floor(String)    // a floor block's raw processor instructions (Stone 7)
        case end
    }
    let kind: Kind
    let line: Int

    // How the token reads in an error message.
    var spoken: String {
        switch kind {
        case .number(let value): return "the number \(formatNumber(value))"
        case .text(let value): return "the text \"\(value)\""
        case .name(let value): return "the name '\(value)'"
        case .keyword(let value): return "'\(value)'"
        case .symbol(let value): return "'\(value)'"
        case .floor: return "a 'floor' block"
        case .end: return "the end of the program"
        }
    }
}

// How a number is written out for people: whole numbers without a
// trailing ".0", decimals plainly.
func formatNumber(_ value: Double) -> String {
    if value == value.rounded() && abs(value) < 1e15 {
        return String(Int(value))
    }
    return String(value)
}

final class Lexer {
    private let chars: [Character]
    private var pos = 0
    private var line = 1

    // Tokens already read and waiting their turn (Stone 9): when a
    // floor block is handed values — floor(value, ...) { ... } —
    // the values' tokens are read while the word 'floor' is being
    // read, so the block itself can be captured right after them;
    // they wait here, behind the 'floor' keyword token, and are
    // handed out before any new reading.
    private var pendingTokens: [Token] = []

    private static let keywords: Set<String> = ["let", "say", "if", "else", "while", "repeat", "for", "in", "make", "give", "true", "false", "floor", "attempt"]

    init(_ source: String) {
        chars = Array(source)
    }

    private var atEnd: Bool { pos >= chars.count }

    private func peek() -> Character? {
        atEnd ? nil : chars[pos]
    }

    private func peekNext() -> Character? {
        pos + 1 < chars.count ? chars[pos + 1] : nil
    }

    func tokenize() throws -> [Token] {
        var tokens: [Token] = []
        while true {
            let token: Token
            if !pendingTokens.isEmpty {
                token = pendingTokens.removeFirst()
            } else if let next = try nextToken() {
                token = next
            } else {
                break
            }
            tokens.append(token)
            if case .end = token.kind { break }
        }
        return tokens
    }

    private func nextToken() throws -> Token? {
        // Skip spaces and blank lines; remember line numbers.
        while let c = peek() {
            if c == "\n" {
                line += 1
                pos += 1
            } else if c == " " || c == "\t" || c == "\r" {
                pos += 1
            } else {
                break
            }
        }
        guard let c = peek() else {
            return Token(kind: .end, line: line)
        }
        let startLine = line

        // A // comment runs to the end of the line.
        if c == "/" && peekNext() == "/" {
            while let ch = peek(), ch != "\n" { pos += 1 }
            return try nextToken()
        }

        if c.isNumber {
            return try lexNumber(startLine)
        }
        if c == "\"" {
            return try lexText(startLine)
        }
        if c.isLetter || c == "_" {
            return try lexWord(startLine)
        }

        // Two-character symbols first, so "=" and "==" stay distinct.
        if let next = peekNext() {
            let pair = String([c, next])
            if ["==", "!=", "<=", ">="].contains(pair) {
                pos += 2
                return Token(kind: .symbol(pair), line: startLine)
            }
        }
        if "+-*/(){}[]=<>.,:".contains(c) {
            pos += 1
            return Token(kind: .symbol(String(c)), line: startLine)
        }
        if c == "!" {
            throw NiflaError(line: startLine, message: "I found a '!' on its own. To say 'not equal', write '!=' — an exclamation mark followed by an equals sign.")
        }
        throw NiflaError(line: startLine, message: "I don't understand the character '\(c)'. Nifla programs are made of words, numbers, text in \"quotes\", and the signs + - * / ( ) { } [ ] , . : = == != < <= > >=.")
    }

    // Captures a floor block's raw lines (Stone 7): called just
    // after the '{' that opens the block has been read. Nothing
    // else belongs on the opening line; the lines below it are
    // taken whole, exactly as written, until a line holding
    // only '}'.
    private func captureFloorLines(startLine: Int) throws -> String {
        while let c = peek(), c == " " || c == "\t" { pos += 1 }
        if peek() == "/", peekNext() == "/" {
            while let c = peek(), c != "\n" { pos += 1 }
        }
        guard peek() == "\n" || atEnd else {
            throw NiflaError(line: startLine, message: "After 'floor {' the processor instructions go on the lines below it, one per line, until a line holding only '}'. Take anything else off this line.")
        }
        if peek() == "\n" { pos += 1; line += 1 }
        var asmLines: [String] = []
        while true {
            guard !atEnd else {
                throw NiflaError(line: startLine, message: "This 'floor' block is never closed. Add a line holding only '}' to finish it.")
            }
            var text = ""
            while let c = peek(), c != "\n" {
                text.append(c)
                pos += 1
            }
            if peek() == "\n" { pos += 1; line += 1 }
            if text.trimmingCharacters(in: .whitespaces) == "}" { break }
            asmLines.append(text)
        }
        return asmLines.joined(separator: "\n")
    }

    private func lexNumber(_ startLine: Int) throws -> Token {
        var text = ""
        while let c = peek(), c.isNumber {
            text.append(c)
            pos += 1
        }
        // A decimal point counts only when a digit follows it.
        if peek() == ".", let after = peekNext(), after.isNumber {
            text.append(".")
            pos += 1
            while let c = peek(), c.isNumber {
                text.append(c)
                pos += 1
            }
        }
        guard let value = Double(text) else {
            throw NiflaError(line: startLine, message: "I couldn't read '\(text)' as a number.")
        }
        return Token(kind: .number(value), line: startLine)
    }

    private func lexText(_ startLine: Int) throws -> Token {
        pos += 1  // the opening quote
        var value = ""
        while let c = peek() {
            if c == "\"" {
                pos += 1
                return Token(kind: .text(value), line: startLine)
            }
            if c == "\n" {
                throw NiflaError(line: startLine, message: "This text never ends — it runs into the end of the line. Add a closing \" to finish it.")
            }
            if c == "\\" {
                pos += 1
                guard let esc = peek() else { break }
                switch esc {
                case "n": value.append("\n")
                case "t": value.append("\t")
                case "\"": value.append("\"")
                case "\\": value.append("\\")
                default:
                    throw NiflaError(line: startLine, message: "I don't know the escape '\\\(esc)' inside text. The ones I know are \\n (new line), \\t (tab), \\\" (a quote), and \\\\ (a backslash).")
                }
                pos += 1
            } else {
                value.append(c)
                pos += 1
            }
        }
        throw NiflaError(line: startLine, message: "This text never ends. Add a closing \" to finish it.")
    }

    private func lexWord(_ startLine: Int) throws -> Token {
        var word = ""
        while let c = peek(), c.isLetter || c.isNumber || c == "_" {
            word.append(c)
            pos += 1
        }
        if word == "floor" {
            // A floor block (Stone 7): 'floor' followed on the same
            // line by '{' opens a stretch of raw lines — processor
            // instructions, taken exactly as written — that runs
            // until a line holding only '}'. Those lines are never
            // lexed as Nifla; they are captured whole.
            //
            // Since Stone 9 a floor block can be handed values:
            // 'floor(value, ...)' followed by '{' on the same line.
            // The values are ordinary Nifla, so their tokens are
            // read here (parentheses counted, text read as text)
            // and queued behind the 'floor' keyword token; the
            // block is captured right after them, as before.
            let savedPos = pos
            while let c = peek(), c == " " || c == "\t" { pos += 1 }
            if peek() == "{" {
                pos += 1  // the '{'
                let asm = try captureFloorLines(startLine: startLine)
                return Token(kind: .floor(asm), line: startLine)
            }
            if peek() == "(" {
                var collected: [Token] = []
                var depth = 0
                while true {
                    guard let token = try nextToken() else {
                        throw NiflaError(line: startLine, message: "The '(' after 'floor' is never closed. Close the values being handed to the block with ')', then give the block itself: floor(values) { ... }.")
                    }
                    if case .end = token.kind {
                        throw NiflaError(line: startLine, message: "The '(' after 'floor' is never closed. Close the values being handed to the block with ')', then give the block itself: floor(values) { ... }.")
                    }
                    collected.append(token)
                    if case .symbol(let symbol) = token.kind {
                        if symbol == "(" { depth += 1 }
                        if symbol == ")" {
                            depth -= 1
                            if depth == 0 { break }
                        }
                    }
                }
                while let c = peek(), c == " " || c == "\t" { pos += 1 }
                guard peek() == "{" else {
                    throw NiflaError(line: startLine, message: "After the values handed to 'floor' I need the block itself: '{' on the same line, then the processor instructions on the lines below, until a line holding only '}'.")
                }
                pos += 1  // the '{'
                let asm = try captureFloorLines(startLine: startLine)
                pendingTokens = collected + [Token(kind: .floor(asm), line: startLine)]
                return Token(kind: .keyword("floor"), line: startLine)
            }
            pos = savedPos
        }
        if Lexer.keywords.contains(word) {
            return Token(kind: .keyword(word), line: startLine)
        }
        return Token(kind: .name(word), line: startLine)
    }
}
