// Nifla — Stone 1 interpreter: the parser.
//
// Reads the lexer's tokens and builds a small tree of statements and
// expressions for the interpreter to walk. Grammar, in plain words:
//
//   statement  = "let" name "=" expression
//              | name "=" expression
//              | "say" expression
//              | "if" expression block [ "else" block ]
//   block      = "{" statement* "}"
//   expression = comparison ( ("==" | "!=") comparison )*
//   comparison = sum ( ("<" | "<=" | ">" | ">=") sum )*
//   sum        = term ( ("+" | "-") term )*
//   term       = factor ( ("*" | "/") factor )*
//   factor     = "-" factor | atom
//   atom       = number | text | "true" | "false" | name | "(" expression ")"

indirect enum Expr {
    case number(Double, line: Int)
    case text(String, line: Int)
    case boolean(Bool, line: Int)
    case variable(String, line: Int)
    case negate(Expr, line: Int)
    case binary(Expr, String, Expr, line: Int)  // line of the operator
}

enum Stmt {
    case declare(name: String, value: Expr, line: Int)
    case assign(name: String, value: Expr, line: Int)
    case say(Expr, line: Int)
    case ifElse(condition: Expr, then: [Stmt], otherwise: [Stmt]?, line: Int)
}

final class Parser {
    private let tokens: [Token]
    private var pos = 0

    init(_ tokens: [Token]) {
        self.tokens = tokens
    }

    private var current: Token { tokens[min(pos, tokens.count - 1)] }

    private func advance() {
        if pos < tokens.count - 1 { pos += 1 }
    }

    private func checkSymbol(_ symbol: String) -> Bool {
        if case .symbol(let value) = current.kind { return value == symbol }
        return false
    }

    private func checkKeyword(_ keyword: String) -> Bool {
        if case .keyword(let value) = current.kind { return value == keyword }
        return false
    }

    func parseProgram() throws -> [Stmt] {
        var statements: [Stmt] = []
        while true {
            if case .end = current.kind { break }
            statements.append(try parseStatement())
        }
        return statements
    }

    private func parseBlock(openLine: Int) throws -> [Stmt] {
        var statements: [Stmt] = []
        while !checkSymbol("}") {
            if case .end = current.kind {
                throw NiflaError(line: openLine, message: "This '{' is never closed. Add a '}' to finish the block it starts.")
            }
            statements.append(try parseStatement())
        }
        advance()  // the closing '}'
        return statements
    }

    private func parseStatement() throws -> Stmt {
        let token = current

        if checkKeyword("let") {
            advance()
            guard case .name(let name) = current.kind else {
                throw NiflaError(line: current.line, message: "After 'let' I need a name for the new variable, like: let years = 29. Instead I found \(current.spoken).")
            }
            advance()
            guard checkSymbol("=") else {
                throw NiflaError(line: current.line, message: "After 'let \(name)' I need an '=' and then a value, like: let \(name) = 29. Instead I found \(current.spoken).")
            }
            advance()
            let value = try parseExpression()
            return .declare(name: name, value: value, line: token.line)
        }

        if checkKeyword("say") {
            advance()
            let value = try parseExpression()
            return .say(value, line: token.line)
        }

        if checkKeyword("if") {
            advance()
            let condition = try parseExpression()
            guard checkSymbol("{") else {
                if checkSymbol("=") {
                    throw NiflaError(line: current.line, message: "After the 'if' condition I expected '{' but found '='. To compare two things, use '==' — two equals signs. A single '=' sets a variable.")
                }
                throw NiflaError(line: current.line, message: "After the 'if' condition I need a '{' to start the block that runs when it's true. Instead I found \(current.spoken).")
            }
            let openLine = current.line
            advance()
            let thenBlock = try parseBlock(openLine: openLine)
            var elseBlock: [Stmt]? = nil
            if checkKeyword("else") {
                advance()
                guard checkSymbol("{") else {
                    throw NiflaError(line: current.line, message: "After 'else' I need a '{' to start the block that runs when the condition is false. Instead I found \(current.spoken).")
                }
                let elseOpenLine = current.line
                advance()
                elseBlock = try parseBlock(openLine: elseOpenLine)
            }
            return .ifElse(condition: condition, then: thenBlock, otherwise: elseBlock, line: token.line)
        }

        // Setting an existing variable: a name followed by '='.
        if case .name(let name) = token.kind {
            let next = tokens[min(pos + 1, tokens.count - 1)]
            if case .symbol(let symbol) = next.kind, symbol == "=" {
                advance()  // the name
                advance()  // the '='
                let value = try parseExpression()
                return .assign(name: name, value: value, line: token.line)
            }
            throw NiflaError(line: token.line, message: "I found the name '\(name)' at the start of a line, but a line needs to do something: make a variable with 'let \(name) = ...', set it with '\(name) = ...', or show it with 'say \(name)'.")
        }

        throw NiflaError(line: token.line, message: "I expected a line to start with 'let', 'say', 'if', or the name of a variable to set — but I found \(token.spoken).")
    }

    private func parseExpression() throws -> Expr {
        try parseEquality()
    }

    private func parseEquality() throws -> Expr {
        var left = try parseComparison()
        while checkSymbol("==") || checkSymbol("!=") {
            let opToken = current
            guard case .symbol(let op) = opToken.kind else { break }
            advance()
            let right = try parseComparison()
            left = .binary(left, op, right, line: opToken.line)
        }
        return left
    }

    private func parseComparison() throws -> Expr {
        var left = try parseSum()
        while checkSymbol("<") || checkSymbol("<=") || checkSymbol(">") || checkSymbol(">=") {
            let opToken = current
            guard case .symbol(let op) = opToken.kind else { break }
            advance()
            let right = try parseSum()
            left = .binary(left, op, right, line: opToken.line)
        }
        return left
    }

    private func parseSum() throws -> Expr {
        var left = try parseTerm()
        while checkSymbol("+") || checkSymbol("-") {
            let opToken = current
            guard case .symbol(let op) = opToken.kind else { break }
            advance()
            let right = try parseTerm()
            left = .binary(left, op, right, line: opToken.line)
        }
        return left
    }

    private func parseTerm() throws -> Expr {
        var left = try parseFactor()
        while checkSymbol("*") || checkSymbol("/") {
            let opToken = current
            guard case .symbol(let op) = opToken.kind else { break }
            advance()
            let right = try parseFactor()
            left = .binary(left, op, right, line: opToken.line)
        }
        return left
    }

    private func parseFactor() throws -> Expr {
        if checkSymbol("-") {
            let opToken = current
            advance()
            return .negate(try parseFactor(), line: opToken.line)
        }
        return try parseAtom()
    }

    private func parseAtom() throws -> Expr {
        let token = current
        switch token.kind {
        case .number(let value):
            advance()
            return .number(value, line: token.line)
        case .text(let value):
            advance()
            return .text(value, line: token.line)
        case .keyword("true"):
            advance()
            return .boolean(true, line: token.line)
        case .keyword("false"):
            advance()
            return .boolean(false, line: token.line)
        case .name(let name):
            advance()
            return .variable(name, line: token.line)
        case .symbol("("):
            advance()
            let inner = try parseExpression()
            guard checkSymbol(")") else {
                throw NiflaError(line: current.line, message: "I expected a ')' to close the '(' from line \(token.line), but I found \(current.spoken).")
            }
            advance()
            return inner
        default:
            throw NiflaError(line: token.line, message: "I expected a number, a piece of text, true, false, or a variable name here, but I found \(token.spoken).")
        }
    }
}
