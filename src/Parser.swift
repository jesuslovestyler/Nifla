// Nifla — Stone 1 interpreter: the parser.
//
// Reads the lexer's tokens and builds a small tree of statements and
// expressions for the interpreter to walk. Grammar, in plain words:
//
//   statement  = "let" name "=" expression
//              | name "=" expression
//              | name ( "." name )+ "=" expression
//              | "say" expression
//              | "if" expression block [ "else" block ]
//              | "while" expression block
//              | "repeat" expression block
//              | "make" name "(" [ name ( "," name )* ] ")" block
//              | "give" expression
//              | name "(" [ expression ( "," expression )* ] ")"
//   block      = "{" statement* "}"
//   expression = comparison ( ("==" | "!=") comparison )*
//   comparison = sum ( ("<" | "<=" | ">" | ">=") sum )*
//   sum        = term ( ("+" | "-") term )*
//   term       = factor ( ("*" | "/") factor )*
//   factor     = "-" factor | postfix
//   postfix    = atom ( "." name )*
//   atom       = number | text | "true" | "false" | name
//              | name "(" [ expression ( "," expression )* ] ")"
//              | "(" expression ")"
//              | "{" [ name ":" expression ( "," name ":" expression )* ] "}"

indirect enum Expr {
    case number(Double, line: Int)
    case text(String, line: Int)
    case boolean(Bool, line: Int)
    case variable(String, line: Int)
    case call(name: String, args: [Expr], line: Int)
    case object(fields: [(name: String, value: Expr)], line: Int)
    case field(base: Expr, name: String, line: Int)
    case negate(Expr, line: Int)
    case binary(Expr, String, Expr, line: Int)  // line of the operator
}

enum Stmt {
    case declare(name: String, value: Expr, line: Int)
    case assign(name: String, value: Expr, line: Int)
    case assignField(target: Expr, value: Expr, line: Int)  // target is a .field chain
    case say(Expr, line: Int)
    case ifElse(condition: Expr, then: [Stmt], otherwise: [Stmt]?, line: Int)
    case whileLoop(condition: Expr, body: [Stmt], line: Int)
    case repeatLoop(count: Expr, body: [Stmt], line: Int)
    case define(name: String, params: [String], body: [Stmt], line: Int)
    case give(Expr, line: Int)
    case doCall(name: String, args: [Expr], line: Int)
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

        if checkKeyword("while") {
            advance()
            let condition = try parseExpression()
            guard checkSymbol("{") else {
                if checkSymbol("=") {
                    throw NiflaError(line: current.line, message: "After the 'while' condition I expected '{' but found '='. To compare two things, use '==' — two equals signs. A single '=' sets a variable.")
                }
                throw NiflaError(line: current.line, message: "After the 'while' condition I need a '{' to start the block that runs again and again while it's true. Instead I found \(current.spoken).")
            }
            let openLine = current.line
            advance()
            let body = try parseBlock(openLine: openLine)
            return .whileLoop(condition: condition, body: body, line: token.line)
        }

        if checkKeyword("repeat") {
            advance()
            let count = try parseExpression()
            guard checkSymbol("{") else {
                throw NiflaError(line: current.line, message: "After the 'repeat' count I need a '{' to start the block that runs that many times, like: repeat 3 { ... }. Instead I found \(current.spoken).")
            }
            let openLine = current.line
            advance()
            let body = try parseBlock(openLine: openLine)
            return .repeatLoop(count: count, body: body, line: token.line)
        }

        if checkKeyword("make") {
            advance()
            guard case .name(let name) = current.kind else {
                throw NiflaError(line: current.line, message: "After 'make' I need a name for the new function, like: make greet(name) { ... }. Instead I found \(current.spoken).")
            }
            advance()
            guard checkSymbol("(") else {
                throw NiflaError(line: current.line, message: "After the function's name I need '(' and the names of the values it takes, like: make \(name)(name) { ... }. Instead I found \(current.spoken).")
            }
            advance()  // the '('
            var params: [String] = []
            if !checkSymbol(")") {
                while true {
                    guard case .name(let param) = current.kind else {
                        throw NiflaError(line: current.line, message: "Inside the parentheses of 'make \(name)' I need names for the values, separated by commas, like: make \(name)(a, b) { ... }. Instead I found \(current.spoken).")
                    }
                    if params.contains(param) {
                        throw NiflaError(line: current.line, message: "The function '\(name)' uses the name '\(param)' twice in its list of values. Each value needs its own name.")
                    }
                    params.append(param)
                    advance()
                    if checkSymbol(",") {
                        advance()
                        continue
                    }
                    break
                }
            }
            guard checkSymbol(")") else {
                throw NiflaError(line: current.line, message: "I expected a ')' to close the list of values for '\(name)', but I found \(current.spoken).")
            }
            advance()  // the ')'
            guard checkSymbol("{") else {
                throw NiflaError(line: current.line, message: "After 'make \(name)(...)' I need a '{' to start the block that runs when the function is called. Instead I found \(current.spoken).")
            }
            let openLine = current.line
            advance()
            let body = try parseBlock(openLine: openLine)
            return .define(name: name, params: params, body: body, line: token.line)
        }

        if checkKeyword("give") {
            advance()
            let value = try parseExpression()
            return .give(value, line: token.line)
        }

        // Setting an existing variable: a name followed by '='.
        // Setting a field: a name followed by one or more '.field'
        // steps and then '='.
        // Calling a function for what it does: a name followed by '('.
        if case .name(let name) = token.kind {
            let next = tokens[min(pos + 1, tokens.count - 1)]
            if case .symbol(let symbol) = next.kind, symbol == "=" {
                advance()  // the name
                advance()  // the '='
                let value = try parseExpression()
                return .assign(name: name, value: value, line: token.line)
            }
            if case .symbol(let symbol) = next.kind, symbol == "." {
                advance()  // the name
                var target: Expr = .variable(name, line: token.line)
                while checkSymbol(".") {
                    let dotToken = current
                    advance()  // the '.'
                    guard case .name(let fieldName) = current.kind else {
                        throw NiflaError(line: current.line, message: "After '.' I need the name of a field, like: \(name).years. Instead I found \(current.spoken).")
                    }
                    advance()
                    target = .field(base: target, name: fieldName, line: dotToken.line)
                }
                guard checkSymbol("=") else {
                    throw NiflaError(line: current.line, message: "A line that starts with a field like this needs to set it: write an '=' and the new value, like: \(name).years = 30. To show a field instead, write: say \(name).years.")
                }
                advance()  // the '='
                let value = try parseExpression()
                return .assignField(target: target, value: value, line: token.line)
            }
            if case .symbol(let symbol) = next.kind, symbol == "(" {
                advance()  // the name
                let args = try parseCallArgs(name: name)
                return .doCall(name: name, args: args, line: token.line)
            }
            throw NiflaError(line: token.line, message: "I found the name '\(name)' at the start of a line, but a line needs to do something: make a variable with 'let \(name) = ...', set it with '\(name) = ...', set a field with '\(name).field = ...', show it with 'say \(name)', or call a function with '\(name)(...)'.")
        }

        throw NiflaError(line: token.line, message: "I expected a line to start with 'let', 'say', 'if', 'while', 'repeat', 'make', 'give', or the name of a variable to set — but I found \(token.spoken).")
    }

    // The "( value, value )" part of a call, shared by call statements
    // and calls inside expressions. The current token is the '('.
    private func parseCallArgs(name: String) throws -> [Expr] {
        advance()  // the '('
        var args: [Expr] = []
        if !checkSymbol(")") {
            args.append(try parseExpression())
            while checkSymbol(",") {
                advance()
                args.append(try parseExpression())
            }
        }
        guard checkSymbol(")") else {
            throw NiflaError(line: current.line, message: "I expected a ')' to close the '(' in this call to '\(name)', but I found \(current.spoken).")
        }
        advance()  // the ')'
        return args
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
        return try parsePostfix()
    }

    // An atom followed by any number of '.field' steps: person.name,
    // person.home.town, and so on. Each step reads one field of the
    // object the steps before it reached.
    private func parsePostfix() throws -> Expr {
        var expr = try parseAtom()
        while checkSymbol(".") {
            let dotToken = current
            advance()  // the '.'
            guard case .name(let fieldName) = current.kind else {
                throw NiflaError(line: current.line, message: "After '.' I need the name of a field, like: person.name. Instead I found \(current.spoken).")
            }
            advance()
            expr = .field(base: expr, name: fieldName, line: dotToken.line)
        }
        return expr
    }

    // An object literal: '{' then name ':' value pairs separated by
    // commas, then '}'. An object with no fields at all is '{ }'
    // written without the space: '{}'.
    private func parseObjectLiteral(openToken: Token) throws -> Expr {
        advance()  // the '{'
        var fields: [(name: String, value: Expr)] = []
        if !checkSymbol("}") {
            while true {
                guard case .name(let fieldName) = current.kind else {
                    throw NiflaError(line: current.line, message: "Inside an object I need field names with values, like: { name: \"Tyler\", years: 29 }. Instead I found \(current.spoken).")
                }
                let fieldLine = current.line
                advance()
                guard checkSymbol(":") else {
                    throw NiflaError(line: current.line, message: "After the field name '\(fieldName)' I need a ':' and then its value, like: { \(fieldName): 29 }. Instead I found \(current.spoken).")
                }
                advance()  // the ':'
                if fields.contains(where: { $0.name == fieldName }) {
                    throw NiflaError(line: fieldLine, message: "This object names the field '\(fieldName)' twice. Each field needs its own name — take one of the two out.")
                }
                let value = try parseExpression()
                fields.append((name: fieldName, value: value))
                if checkSymbol(",") {
                    advance()
                    continue
                }
                break
            }
        }
        guard checkSymbol("}") else {
            throw NiflaError(line: current.line, message: "I expected a '}' to close the object that started on line \(openToken.line), but I found \(current.spoken).")
        }
        advance()  // the '}'
        return .object(fields: fields, line: openToken.line)
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
            if checkSymbol("(") {
                let args = try parseCallArgs(name: name)
                return .call(name: name, args: args, line: token.line)
            }
            return .variable(name, line: token.line)
        case .symbol("("):
            advance()
            let inner = try parseExpression()
            guard checkSymbol(")") else {
                throw NiflaError(line: current.line, message: "I expected a ')' to close the '(' from line \(token.line), but I found \(current.spoken).")
            }
            advance()
            return inner
        case .symbol("{"):
            return try parseObjectLiteral(openToken: token)
        default:
            throw NiflaError(line: token.line, message: "I expected a number, a piece of text, true, false, a variable name, or an object like { name: \"Tyler\" } here, but I found \(token.spoken).")
        }
    }
}
