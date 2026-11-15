// Nifla — Stone 1 interpreter: the parser.
//
// Reads the lexer's tokens and builds a small tree of statements and
// expressions for the interpreter to walk. Grammar, in plain words:
//
//   statement  = "let" name "=" expression
//              | name "=" expression
//              | name ( "." name | "[" expression "]" )+ "=" expression
//              | "say" expression
//              | "if" expression block [ "else" block ]
//              | "while" expression block
//              | "repeat" expression block
//              | "for" name "in" expression block
//              | "make" name "(" [ name ( "," name )* ] ")" block
//              | "give" expression
//              | "attempt" block "if" "it" "fails" block
//              | name "(" [ expression ( "," expression )* ] ")"
//              | floor-block
//   block      = "{" statement* "}"
//   expression = comparison ( ("==" | "!=") comparison )*
//   comparison = sum ( ("<" | "<=" | ">" | ">=") sum )*
//   sum        = term ( ("+" | "-") term )*
//   term       = factor ( ("*" | "/") factor )*
//   factor     = "-" factor | postfix
//   postfix    = atom ( "." name | "[" expression "]" )*
//   atom       = number | text | "true" | "false" | name
//              | name "(" [ expression ( "," expression )* ] ")"
//              | "(" expression ")"
//              | "{" [ name ":" expression ( "," name ":" expression )* ] "}"
//              | "[" [ expression ( "," expression )* ] "]"
//              | floor-block
//   floor-block = "floor" [ "(" [ expression ( "," expression )* ] ")" ]
//              "{" — then raw lines of processor instructions, taken
//              whole by the lexer, until a line holding only "}"
//              (Stone 7; the values it can be handed, Stone 9)

indirect enum Expr {
    case number(Double, line: Int)
    case text(String, line: Int)
    case boolean(Bool, line: Int)
    case variable(String, line: Int)
    case call(name: String, args: [Expr], line: Int)
    case object(fields: [(name: String, value: Expr)], line: Int)
    case list(items: [Expr], line: Int)
    case field(base: Expr, name: String, line: Int)
    case index(base: Expr, index: Expr, line: Int)
    case floor(asm: String, args: [Expr], line: Int)
    case negate(Expr, line: Int)
    case binary(Expr, String, Expr, line: Int)  // line of the operator
}

enum Stmt {
    // Stone 18: a 'let' may carry an optional kind annotation
    // (let name: number = ...), and a 'make' may annotate its
    // parameters (make f(a: number)) and the kind it gives back
    // (make f(...) -> number). The annotation is the kind's word
    // as written, or nil when there is none — most code has none.
    case declare(name: String, kind: String?, value: Expr, line: Int)
    case assign(name: String, value: Expr, line: Int)
    case assignTarget(target: Expr, value: Expr, line: Int)  // target ends in a .field or [index] step
    case say(Expr, line: Int)
    case ifElse(condition: Expr, then: [Stmt], otherwise: [Stmt]?, line: Int)
    case whileLoop(condition: Expr, body: [Stmt], line: Int)
    case repeatLoop(count: Expr, body: [Stmt], line: Int)
    case forEach(name: String, over: Expr, body: [Stmt], line: Int)
    case define(name: String, params: [String], paramKinds: [String?], returnKind: String?, body: [Stmt], line: Int)
    case give(Expr, line: Int)
    case attempt(body: [Stmt], recovery: [Stmt], line: Int)
    case doCall(name: String, args: [Expr], line: Int)
    case doExpr(Expr, line: Int)  // an expression run for what it does (a floor block, Stone 7)
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

    // The kinds a value may be marked as (Stone 18) — the
    // checker's own vocabulary, plus 'nothing' for a function
    // that promises to give nothing back.
    static let kindWords: Set<String> = ["number", "text", "boolean", "list", "object", "bytes", "nothing"]

    // Reads one kind word where an annotation stands. The word
    // arrives as a name token; anything else — or a name that
    // isn't a kind — is refused in plain words.
    private func parseKindWord(after: String) throws -> String {
        guard case .name(let word) = current.kind else {
            throw NiflaError(line: current.line, message: "After the \(after) I need a kind — one of: number, text, boolean, list, object, bytes, nothing. Instead I found \(current.spoken).")
        }
        guard Parser.kindWords.contains(word) else {
            throw NiflaError(line: current.line, message: "I don't know a kind called '\(word)'. The kinds a value can be marked as are: number, text, boolean, list, object, bytes, nothing.")
        }
        advance()
        return word
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

        // A floor block standing on its own: run it for what it
        // does, and let the value it gives back go.
        if case .floor(let asm) = token.kind {
            advance()
            return .doExpr(.floor(asm: asm, args: [], line: token.line), line: token.line)
        }

        // A floor block handed values (Stone 9), standing on its
        // own line: the same — run it for what it does.
        if checkKeyword("floor") {
            let value = try parseExpression()
            return .doExpr(value, line: token.line)
        }

        if checkKeyword("let") {
            advance()
            guard case .name(let name) = current.kind else {
                throw NiflaError(line: current.line, message: "After 'let' I need a name for the new variable, like: let years = 29. Instead I found \(current.spoken).")
            }
            advance()
            // Stone 18: an optional kind annotation —
            // let years: number = 29.
            var kind: String? = nil
            if checkSymbol(":") {
                advance()
                kind = try parseKindWord(after: "':' after 'let \(name)'")
            }
            guard checkSymbol("=") else {
                throw NiflaError(line: current.line, message: "After 'let \(name)' I need an '=' and then a value, like: let \(name) = 29. Instead I found \(current.spoken).")
            }
            advance()
            let value = try parseExpression()
            return .declare(name: name, kind: kind, value: value, line: token.line)
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

        if checkKeyword("for") {
            advance()
            guard case .name(let name) = current.kind else {
                throw NiflaError(line: current.line, message: "After 'for' I need a name for each item the loop walks through, like: for item in items { ... }. Instead I found \(current.spoken).")
            }
            advance()
            guard checkKeyword("in") else {
                throw NiflaError(line: current.line, message: "After 'for \(name)' I need 'in' and then the list or text to walk through, like: for \(name) in items { ... }. Instead I found \(current.spoken).")
            }
            advance()
            let over = try parseExpression()
            guard checkSymbol("{") else {
                throw NiflaError(line: current.line, message: "After 'for \(name) in ...' I need a '{' to start the block that runs for each item. Instead I found \(current.spoken).")
            }
            let openLine = current.line
            advance()
            let body = try parseBlock(openLine: openLine)
            return .forEach(name: name, over: over, body: body, line: token.line)
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
            var paramKinds: [String?] = []
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
                    // Stone 18: an optional kind annotation on
                    // the value — make greet(name: text) { ... }.
                    var paramKind: String? = nil
                    if checkSymbol(":") {
                        advance()
                        paramKind = try parseKindWord(after: "':' after '\(param)'")
                    }
                    paramKinds.append(paramKind)
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
            // Stone 18: an optional promised kind after the
            // arrow — make twice(n: number) -> number { ... }.
            var returnKind: String? = nil
            if checkSymbol("->") {
                advance()
                returnKind = try parseKindWord(after: "'->' in 'make \(name)'")
            }
            guard checkSymbol("{") else {
                throw NiflaError(line: current.line, message: "After 'make \(name)(...)' I need a '{' to start the block that runs when the function is called. Instead I found \(current.spoken).")
            }
            let openLine = current.line
            advance()
            let body = try parseBlock(openLine: openLine)
            return .define(name: name, params: params, paramKinds: paramKinds, returnKind: returnKind, body: body, line: token.line)
        }

        if checkKeyword("give") {
            advance()
            let value = try parseExpression()
            return .give(value, line: token.line)
        }

        if checkKeyword("attempt") {
            // attempt { ... } if it fails { ... } — do something
            // that might go wrong, and say what to do when it does
            // (Stone 10). The 'if it fails' is part of the shape:
            // those three words after the block can only mean this
            // (an ordinary 'if' could never be followed by two
            // names in a row), so there is no mistaking them.
            advance()
            guard checkSymbol("{") else {
                throw NiflaError(line: current.line, message: "After 'attempt' I need a '{' to start the block that tries, like: attempt { ... } if it fails { ... }. Instead I found \(current.spoken).")
            }
            let openLine = current.line
            advance()
            let body = try parseBlock(openLine: openLine)
            let itToken = tokens[min(pos + 1, tokens.count - 1)]
            let failsToken = tokens[min(pos + 2, tokens.count - 1)]
            let braceToken = tokens[min(pos + 3, tokens.count - 1)]
            var shape = false
            if checkKeyword("if"),
               case .name(let itWord) = itToken.kind, itWord == "it",
               case .name(let failsWord) = failsToken.kind, failsWord == "fails",
               case .symbol(let brace) = braceToken.kind, brace == "{" {
                shape = true
            }
            guard shape else {
                throw NiflaError(line: current.line, message: "After an 'attempt' block I need 'if it fails' and a block saying what to do when something goes wrong, like: attempt { ... } if it fails { ... }.")
            }
            advance()  // 'if'
            advance()  // 'it'
            advance()  // 'fails'
            let recoveryOpenLine = current.line
            advance()  // '{'
            let recovery = try parseBlock(openLine: recoveryOpenLine)
            return .attempt(body: body, recovery: recovery, line: token.line)
        }

        // Setting an existing variable: a name followed by '='.
        // Setting a field or an item: a name followed by one or
        // more '.field' or '[...]' steps and then '='.
        // Calling a function for what it does: a name followed by '('.
        if case .name(let name) = token.kind {
            let next = tokens[min(pos + 1, tokens.count - 1)]
            if case .symbol(let symbol) = next.kind, symbol == "=" {
                advance()  // the name
                advance()  // the '='
                let value = try parseExpression()
                return .assign(name: name, value: value, line: token.line)
            }
            if case .symbol(let symbol) = next.kind, symbol == "." || symbol == "[" {
                advance()  // the name
                var target: Expr = .variable(name, line: token.line)
                while checkSymbol(".") || checkSymbol("[") {
                    if checkSymbol(".") {
                        let dotToken = current
                        advance()  // the '.'
                        guard case .name(let fieldName) = current.kind else {
                            throw NiflaError(line: current.line, message: "After '.' I need the name of a field, like: \(name).years. Instead I found \(current.spoken).")
                        }
                        advance()
                        target = .field(base: target, name: fieldName, line: dotToken.line)
                    } else {
                        let bracketToken = current
                        advance()  // the '['
                        let indexExpr = try parseExpression()
                        guard checkSymbol("]") else {
                            throw NiflaError(line: current.line, message: "I expected a ']' to close the '[' from line \(bracketToken.line), but I found \(current.spoken).")
                        }
                        advance()  // the ']'
                        target = .index(base: target, index: indexExpr, line: bracketToken.line)
                    }
                }
                guard checkSymbol("=") else {
                    throw NiflaError(line: current.line, message: "A line that starts with a field or an item like this needs to set it: write an '=' and the new value, like: \(name).years = 30 or \(name)[0] = 30. To show it instead, write it after 'say'.")
                }
                advance()  // the '='
                let value = try parseExpression()
                return .assignTarget(target: target, value: value, line: token.line)
            }
            if case .symbol(let symbol) = next.kind, symbol == "(" {
                advance()  // the name
                let args = try parseCallArgs(name: name)
                return .doCall(name: name, args: args, line: token.line)
            }
            throw NiflaError(line: token.line, message: "I found the name '\(name)' at the start of a line, but a line needs to do something: make a variable with 'let \(name) = ...', set it with '\(name) = ...', set a field with '\(name).field = ...', set an item with '\(name)[0] = ...', show it with 'say \(name)', or call a function with '\(name)(...)'.")
        }

        throw NiflaError(line: token.line, message: "I expected a line to start with 'let', 'say', 'if', 'while', 'repeat', 'for', 'make', 'give', 'attempt', or the name of a variable to set — but I found \(token.spoken).")
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

    // An atom followed by any number of steps: '.field' reads one
    // field of an object (person.name, person.home.town), and
    // '[...]' reads one item of a list or one character of some
    // text (items[0], items[0].name, word[2]).
    private func parsePostfix() throws -> Expr {
        var expr = try parseAtom()
        while checkSymbol(".") || checkSymbol("[") {
            if checkSymbol(".") {
                let dotToken = current
                advance()  // the '.'
                guard case .name(let fieldName) = current.kind else {
                    throw NiflaError(line: current.line, message: "After '.' I need the name of a field, like: person.name. Instead I found \(current.spoken).")
                }
                advance()
                expr = .field(base: expr, name: fieldName, line: dotToken.line)
            } else {
                let bracketToken = current
                advance()  // the '['
                let indexExpr = try parseExpression()
                guard checkSymbol("]") else {
                    throw NiflaError(line: current.line, message: "I expected a ']' to close the '[' from line \(bracketToken.line), but I found \(current.spoken).")
                }
                advance()  // the ']'
                expr = .index(base: expr, index: indexExpr, line: bracketToken.line)
            }
        }
        return expr
    }

    // A list literal: '[' then values separated by commas, then
    // ']'. A list with nothing in it is '[]'.
    private func parseListLiteral(openToken: Token) throws -> Expr {
        advance()  // the '['
        var items: [Expr] = []
        if !checkSymbol("]") {
            while true {
                items.append(try parseExpression())
                if checkSymbol(",") {
                    advance()
                    continue
                }
                break
            }
        }
        guard checkSymbol("]") else {
            throw NiflaError(line: current.line, message: "I expected a ']' to close the list that started on line \(openToken.line), but I found \(current.spoken).")
        }
        advance()  // the ']'
        return .list(items: items, line: openToken.line)
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
        case .symbol("["):
            return try parseListLiteral(openToken: token)
        case .floor(let asm):
            advance()
            return .floor(asm: asm, args: [], line: token.line)
        case .keyword("floor"):
            // A floor block handed values (Stone 9): the lexer read
            // the values' tokens and captured the block right after
            // them, so what follows the ')' is the block token.
            advance()
            let args = try parseCallArgs(name: "floor")
            guard case .floor(let asm) = current.kind else {
                throw NiflaError(line: current.line, message: "After the values handed to 'floor' I need the block itself: '{' on the same line, then the processor instructions. Instead I found \(current.spoken).")
            }
            advance()
            return .floor(asm: asm, args: args, line: token.line)
        default:
            throw NiflaError(line: token.line, message: "I expected a number, a piece of text, true, false, a variable name, an object like { name: \"Tyler\" }, a list like [1, 2, 3], or a floor block here, but I found \(token.spoken).")
        }
    }
}
