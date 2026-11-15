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
        case keyword(String)  // let, say, if, else, while, repeat, for, in, make, give, true, false, floor
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

    private static let keywords: Set<String> = ["let", "say", "if", "else", "while", "repeat", "for", "in", "make", "give", "true", "false", "floor"]

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
        while let token = try nextToken() {
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
            let savedPos = pos
            while let c = peek(), c == " " || c == "\t" { pos += 1 }
            if peek() == "{" {
                pos += 1  // the '{'
                // Nothing else belongs on the opening line.
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
                return Token(kind: .floor(asmLines.joined(separator: "\n")), line: startLine)
            }
            pos = savedPos
        }
        if Lexer.keywords.contains(word) {
            return Token(kind: .keyword(word), line: startLine)
        }
        return Token(kind: .name(word), line: startLine)
    }
}
