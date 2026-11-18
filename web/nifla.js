// Nifla on the web — the browser stone.
//
// The Nifla interpreter, written in JavaScript, so a Nifla
// program can run inside a web page. This is the hosted
// language — the world the Tutorial's Lessons 1–8 teach:
// saying and keeping, deciding and repeating, lists and
// objects, making your own tools, kinds and checked absence,
// papers that stay, and standing on its own two feet as far
// as `exitwith`. The checker reads every program before it
// runs and refuses what it can prove wrong, in the same
// plain words the Swift implementation speaks; the run
// answers in the same plain words too, line numbers and all.
// The runaway guards are the same: a million loop passes,
// five hundred calls deep, sixteen megabytes in one block
// of bytes.
//
// What this door does NOT run, honestly: bare metal,
// guests and feathers, and the compiler. Those belong to
// real metal and to niflac. Floor code runs here — on a
// simulated desk that keeps the floor contract the Primer
// tells (see "The floor desk" below): the instructions
// Nifla's own books and tests use are carried out one by
// one, and a block reaching past the desk is refused in
// plain words naming the limit, before anything runs.
//
// Files: a web page has no disk, so `readfile`, `writefile`
// and `readbytes` work on an in-memory paper-store the host
// page seeds and reads back (see `files` below). A name in
// the store is the whole address — there are no folders, so
// a write can only fail the ways the run itself refuses,
// never for a missing folder.
//
// The API:
//
//   Nifla.run(source, options) -> result
//
//   source   the Nifla program, as text.
//   options  optional; may hold:
//     args    a list of text — the words arguments() gives
//             the program (default: none).
//     files   the paper-store to start from: an object
//             mapping a file's name to its contents — text
//             (a string) for a text file, or a Uint8Array
//             for a file held as the bytes it is
//             (default: an empty store).
//
//   result   an object with:
//     output       everything the program said (its
//                  standard output), as one piece of text.
//     errorOutput  everything on the error channel: what
//                  sayerr said, and — when the program was
//                  refused or went wrong — the plain-words
//                  problem, as one piece of text.
//     exitCode     0 when the program ran clean; the
//                  number exitwith left; 1 when the program
//                  was refused or went wrong.
//     error        the plain-words problem, as
//                  "Line N: ..." (no trailing newline), or
//                  null when there was none.
//     files        the paper-store as the run left it —
//                  the same shape as options.files, ready
//                  to hand to the next run.
//
// The file is one file on purpose, with nothing it depends
// on: drop it into a page with a <script> tag (it leaves a
// `Nifla` global behind), or require() it under Node (it
// fills module.exports). The core uses no browser-only and
// no Node-only machinery, so the language behaves the same
// in both houses — the corpus in run-web.sh proves it under
// Node against the same expectations the Swift suites keep.
//
// Part of Nifla, a public-domain programming language by
// Tyler Kovalevich. See the Unlicense in the LICENSE file
// at the root of this repository.

(function (global) {
'use strict';

// ----------------------------------------------------------------
// Plain-words errors. Every problem Nifla finds in a program is
// reported this way: the line, what went wrong, and how to fix
// it. No stack traces ever reach the person writing Nifla.
// ----------------------------------------------------------------

class NiflaError extends Error {
  constructor(line, message) {
    super(message);
    this.line = line;
    this.message = message;
  }
  get spoken() { return 'Line ' + this.line + ': ' + this.message; }
}

// How a 'give' line hands its value back: thrown like an error
// and caught by the call that is running the function. It never
// reaches the person writing Nifla.
class ReturnSignal {
  constructor(value, line) { this.value = value; this.line = line; }
}

// How exitwith ends the program: thrown, and caught only by the
// outermost run, which turns it into the exit code.
class ExitSignal {
  constructor(code) { this.code = code; }
}

// ----------------------------------------------------------------
// Numbers. Nifla's numbers are the machine's doubles, written
// out for people the way the Swift implementation writes them:
// whole numbers without a trailing ".0" (below 1e15); anything
// else in the shortest digits that read back to the same
// number, in plain decimal when the first digit's exponent is
// between -4 and 15, and in scientific writing outside that.
// ----------------------------------------------------------------

function swiftDoubleString(value) {
  if (Number.isNaN(value)) return 'nan';
  if (value === Infinity) return 'inf';
  if (value === -Infinity) return '-inf';
  if (value === 0) return Object.is(value, -0) ? '-0.0' : '0.0';
  const neg = value < 0;
  const abs = Math.abs(value);
  // JavaScript's own writing of a number is also the shortest
  // digits that read back to the same number; take its digits
  // and exponent, then lay them out the Swift way.
  const s = abs.toString();
  let digits, exp;
  const eAt = s.indexOf('e');
  if (eAt >= 0) {
    exp = parseInt(s.slice(eAt + 1), 10);
    digits = s.slice(0, eAt).replace('.', '').replace(/^0+/, '');
  } else if (s.indexOf('.') >= 0) {
    const dot = s.indexOf('.');
    const ip = s.slice(0, dot), fp = s.slice(dot + 1);
    if (ip !== '0') {
      exp = ip.length - 1;
      digits = (ip + fp).replace(/0+$/, '');
    } else {
      let i = 0;
      while (fp[i] === '0') i++;
      exp = -(i + 1);
      digits = fp.slice(i).replace(/0+$/, '');
    }
  } else {
    exp = s.length - 1;
    digits = s.replace(/0+$/, '');
  }
  if (digits === '') { digits = '0'; exp = 0; }
  let out;
  if (exp >= -4 && exp <= 15) {
    const point = exp + 1;
    if (point >= digits.length) {
      out = digits + '0'.repeat(point - digits.length) + '.0';
    } else if (point > 0) {
      out = digits.slice(0, point) + '.' + digits.slice(point);
    } else {
      out = '0.' + '0'.repeat(-point) + digits;
    }
  } else {
    out = digits[0] + (digits.length > 1 ? '.' + digits.slice(1) : '');
    out += 'e' + (exp < 0 ? '-' : '+') + String(Math.abs(exp)).padStart(2, '0');
  }
  return neg ? '-' + out : out;
}

function formatNumber(value) {
  if (Number.isFinite(value) && value === Math.round(value) && Math.abs(value) < 1e15) {
    return String(Math.trunc(value));
  }
  return swiftDoubleString(value);
}

// ----------------------------------------------------------------
// Text. The Swift implementation reads text a character at a
// time, where a character is a whole grapheme — what a person
// counts as one letter, marks and all. Intl.Segmenter counts
// the same way; where it is missing, fall back to code points.
// ----------------------------------------------------------------

const segmenter = (typeof Intl !== 'undefined' && Intl.Segmenter)
  ? new Intl.Segmenter(undefined, { granularity: 'grapheme' })
  : null;

function graphemes(text) {
  if (segmenter) {
    const out = [];
    for (const part of segmenter.segment(text)) out.push(part.segment);
    return out;
  }
  return [...text];
}

function graphemeCount(text) {
  return graphemes(text).length;
}

// Text in letter order: character by character, by the
// characters' own numbers — the plain a-to-z order the
// machine's letters stand in.
function compareText(a, b) {
  const aa = [...a], bb = [...b];
  const n = Math.min(aa.length, bb.length);
  for (let i = 0; i < n; i++) {
    const x = aa[i].codePointAt(0), y = bb[i].codePointAt(0);
    if (x !== y) return x < y ? -1 : 1;
  }
  if (aa.length === bb.length) return 0;
  return aa.length < bb.length ? -1 : 1;
}

function utf8Encode(text) {
  return new TextEncoder().encode(text);
}

function utf8DecodeStrict(bytes) {
  return new TextDecoder('utf-8', { fatal: true }).decode(bytes);
}

// Stone 28: reading bytes as text, the way 'astext' does —
// a run of bytes that is not a letter stands in the text
// as the replacement mark, never dropped, never guessed.
function utf8Decode(bytes) {
  return new TextDecoder('utf-8').decode(bytes);
}

// ----------------------------------------------------------------
// Edit distance between two words, for spelling suggestions.
// ----------------------------------------------------------------

function editDistance(a, b) {
  const aChars = [...a], bChars = [...b];
  if (aChars.length === 0) return bChars.length;
  if (bChars.length === 0) return aChars.length;
  let previous = [];
  for (let j = 0; j <= bChars.length; j++) previous.push(j);
  let current = new Array(bChars.length + 1).fill(0);
  for (let i = 1; i <= aChars.length; i++) {
    current[0] = i;
    for (let j = 1; j <= bChars.length; j++) {
      const cost = aChars[i - 1] === bChars[j - 1] ? 0 : 1;
      current[j] = Math.min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost);
    }
    const swap = previous; previous = current; current = swap;
  }
  return previous[bChars.length];
}

// ----------------------------------------------------------------
// The lexer: turns Nifla source text into a list of tokens,
// remembering which line each token came from so error
// messages can point at the right place.
//
// A token is { kind, value, line } with kind one of:
// 'number' (value a number), 'text', 'name', 'keyword',
// 'symbol', 'floor' (value the block's raw lines), 'end'.
// ----------------------------------------------------------------

const KEYWORDS = new Set(['let', 'say', 'if', 'else', 'while', 'repeat', 'for', 'in', 'make', 'give', 'true', 'false', 'floor', 'attempt', 'nothing']);

function tokenSpoken(token) {
  switch (token.kind) {
    case 'number': return 'the number ' + formatNumber(token.value);
    case 'text': return 'the text "' + token.value + '"';
    case 'name': return "the name '" + token.value + "'";
    case 'keyword': return "'" + token.value + "'";
    case 'symbol': return "'" + token.value + "'";
    case 'floor': return "a 'floor' block";
    default: return 'the end of the program';
  }
}

function isDigitChar(c) { return /[\p{Nd}]/u.test(c); }
function isNumberChar(c) { return /[\p{N}]/u.test(c); }
function isLetterChar(c) { return /[\p{L}]/u.test(c); }

class Lexer {
  constructor(source) {
    this.chars = [...source];
    this.pos = 0;
    this.line = 1;
    // Tokens already read and waiting their turn: when a floor
    // block is handed values — floor(value, ...) { ... } — the
    // values' tokens are read while the word 'floor' is being
    // read, so the block itself can be captured right after
    // them; they wait here, behind the 'floor' keyword token.
    this.pendingTokens = [];
  }

  get atEnd() { return this.pos >= this.chars.length; }
  peek() { return this.atEnd ? undefined : this.chars[this.pos]; }
  peekNext() { return this.pos + 1 < this.chars.length ? this.chars[this.pos + 1] : undefined; }

  tokenize() {
    const tokens = [];
    while (true) {
      let token;
      if (this.pendingTokens.length > 0) {
        token = this.pendingTokens.shift();
      } else {
        token = this.nextToken();
      }
      tokens.push(token);
      if (token.kind === 'end') break;
    }
    return tokens;
  }

  nextToken() {
    while (true) {
      // Skip spaces and blank lines; remember line numbers.
      while (true) {
        const c = this.peek();
        if (c === '\n') { this.line += 1; this.pos += 1; }
        else if (c === ' ' || c === '\t' || c === '\r') { this.pos += 1; }
        else break;
      }
      const c = this.peek();
      if (c === undefined) {
        return { kind: 'end', value: null, line: this.line };
      }
      const startLine = this.line;

      // A // comment runs to the end of the line.
      if (c === '/' && this.peekNext() === '/') {
        while (this.peek() !== undefined && this.peek() !== '\n') this.pos += 1;
        continue;
      }

      if (isDigitChar(c)) return this.lexNumber(startLine);
      if (c === '"') return this.lexText(startLine);
      if (isLetterChar(c) || c === '_') return this.lexWord(startLine);

      // Two-character symbols first, so "=" and "==" stay
      // distinct. ("->" is the arrow that marks a function's
      // promised kind: make f(...) -> number { ... }.)
      const next = this.peekNext();
      if (next !== undefined) {
        const pair = c + next;
        if (pair === '==' || pair === '!=' || pair === '<=' || pair === '>=' || pair === '->') {
          this.pos += 2;
          return { kind: 'symbol', value: pair, line: startLine };
        }
      }
      if ('+-*/(){}[]=<>.,:'.includes(c)) {
        this.pos += 1;
        return { kind: 'symbol', value: c, line: startLine };
      }
      if (c === '!') {
        throw new NiflaError(startLine, "I found a '!' on its own. To say 'not equal', write '!=' — an exclamation mark followed by an equals sign.");
      }
      throw new NiflaError(startLine, "I don't understand the character '" + c + "'. Nifla programs are made of words, numbers, text in \"quotes\", and the signs + - * / ( ) { } [ ] , . : = == != < <= > >=.");
    }
  }

  // Captures a floor block's raw lines: called just after the
  // '{' that opens the block has been read. Nothing else
  // belongs on the opening line; the lines below it are taken
  // whole, exactly as written, until a line holding only '}'.
  captureFloorLines(startLine) {
    while (this.peek() === ' ' || this.peek() === '\t') this.pos += 1;
    if (this.peek() === '/' && this.peekNext() === '/') {
      while (this.peek() !== undefined && this.peek() !== '\n') this.pos += 1;
    }
    if (!(this.peek() === '\n' || this.atEnd)) {
      throw new NiflaError(startLine, "After 'floor {' the processor instructions go on the lines below it, one per line, until a line holding only '}'. Take anything else off this line.");
    }
    if (this.peek() === '\n') { this.pos += 1; this.line += 1; }
    const asmLines = [];
    while (true) {
      if (this.atEnd) {
        throw new NiflaError(startLine, "This 'floor' block is never closed. Add a line holding only '}' to finish it.");
      }
      let text = '';
      while (this.peek() !== undefined && this.peek() !== '\n') {
        text += this.peek();
        this.pos += 1;
      }
      if (this.peek() === '\n') { this.pos += 1; this.line += 1; }
      if (text.trim() === '}') break;
      asmLines.push(text);
    }
    return asmLines.join('\n');
  }

  lexNumber(startLine) {
    let text = '';
    while (this.peek() !== undefined && isNumberChar(this.peek())) {
      text += this.peek();
      this.pos += 1;
    }
    // A decimal point counts only when a digit follows it.
    if (this.peek() === '.') {
      const after = this.peekNext();
      if (after !== undefined && isDigitChar(after)) {
        text += '.';
        this.pos += 1;
        while (this.peek() !== undefined && isNumberChar(this.peek())) {
          text += this.peek();
          this.pos += 1;
        }
      }
    }
    const value = /^[0-9]+(\.[0-9]+)?$/.test(text) ? Number(text) : NaN;
    if (Number.isNaN(value)) {
      throw new NiflaError(startLine, "I couldn't read '" + text + "' as a number.");
    }
    return { kind: 'number', value: value, line: startLine };
  }

  lexText(startLine) {
    this.pos += 1; // the opening quote
    let value = '';
    while (true) {
      const c = this.peek();
      if (c === undefined) break;
      if (c === '"') {
        this.pos += 1;
        return { kind: 'text', value: value, line: startLine };
      }
      if (c === '\n') {
        throw new NiflaError(startLine, 'This text never ends — it runs into the end of the line. Add a closing " to finish it.');
      }
      if (c === '\\') {
        this.pos += 1;
        const esc = this.peek();
        if (esc === undefined) break;
        switch (esc) {
          case 'n': value += '\n'; break;
          case 't': value += '\t'; break;
          case '"': value += '"'; break;
          case '\\': value += '\\'; break;
          default:
            throw new NiflaError(startLine, "I don't know the escape '\\" + esc + "' inside text. The ones I know are \\n (new line), \\t (tab), \\\" (a quote), and \\\\ (a backslash).");
        }
        this.pos += 1;
      } else {
        value += c;
        this.pos += 1;
      }
    }
    throw new NiflaError(startLine, 'This text never ends. Add a closing " to finish it.');
  }

  lexWord(startLine) {
    let word = '';
    while (true) {
      const c = this.peek();
      if (c !== undefined && (isLetterChar(c) || isNumberChar(c) || c === '_')) {
        word += c;
        this.pos += 1;
      } else break;
    }
    if (word === 'floor') {
      // A floor block: 'floor' followed on the same line by
      // '{' opens a stretch of raw lines, taken exactly as
      // written, until a line holding only '}'. Those lines
      // are never lexed as Nifla; they are captured whole.
      // A floor block can also be handed values:
      // 'floor(value, ...)' followed by '{' on the same line.
      // The values are ordinary Nifla, so their tokens are
      // read here and queued behind the 'floor' keyword
      // token; the block is captured right after them.
      const savedPos = this.pos;
      while (this.peek() === ' ' || this.peek() === '\t') this.pos += 1;
      if (this.peek() === '{') {
        this.pos += 1; // the '{'
        const asm = this.captureFloorLines(startLine);
        return { kind: 'floor', value: asm, line: startLine };
      }
      if (this.peek() === '(') {
        const collected = [];
        let depth = 0;
        while (true) {
          const token = this.nextToken();
          if (token.kind === 'end') {
            throw new NiflaError(startLine, "The '(' after 'floor' is never closed. Close the values being handed to the block with ')', then give the block itself: floor(values) { ... }.");
          }
          collected.push(token);
          if (token.kind === 'symbol') {
            if (token.value === '(') depth += 1;
            if (token.value === ')') {
              depth -= 1;
              if (depth === 0) break;
            }
          }
        }
        while (this.peek() === ' ' || this.peek() === '\t') this.pos += 1;
        if (this.peek() !== '{') {
          throw new NiflaError(startLine, "After the values handed to 'floor' I need the block itself: '{' on the same line, then the processor instructions on the lines below, until a line holding only '}'.");
        }
        this.pos += 1; // the '{'
        const asm = this.captureFloorLines(startLine);
        this.pendingTokens = collected.concat([{ kind: 'floor', value: asm, line: startLine }]);
        return { kind: 'keyword', value: 'floor', line: startLine };
      }
      this.pos = savedPos;
    }
    if (KEYWORDS.has(word)) {
      return { kind: 'keyword', value: word, line: startLine };
    }
    return { kind: 'name', value: word, line: startLine };
  }
}

// ----------------------------------------------------------------
// The parser: reads the lexer's tokens and builds a small tree
// of statements and expressions for the interpreter to walk.
// (The grammar stands in plain words at the head of the Swift
// parser, Parser.swift, and is the same here, word for word.)
//
// Expressions are objects with a `t`:
//   num {v} · text {v} · bool {v} · nothing · var {name} ·
//   call {name, args} · object {fields:[{name, value}]} ·
//   list {items} · field {base, name} · index {base, index} ·
//   floor {asm, args} · neg {inner} · bin {left, op, right}
// Statements likewise:
//   declare {name, kind, value} · assign {name, value} ·
//   assignTarget {target, value} · say {value} ·
//   if {cond, then, otherwise} · while {cond, body} ·
//   repeat {count, body} · for {name, over, body} ·
//   define {name, params, paramKinds, returnKind, body} ·
//   give {value} · attempt {body, recovery} ·
//   doCall {name, args} · doExpr {expr}
// Every node carries the line it stands on.
// ----------------------------------------------------------------

const KIND_WORDS = new Set(['number', 'text', 'boolean', 'list', 'object', 'bytes', 'nothing']);

class Parser {
  constructor(tokens) {
    this.tokens = tokens;
    this.pos = 0;
  }

  get current() { return this.tokens[Math.min(this.pos, this.tokens.length - 1)]; }
  peekAt(offset) { return this.tokens[Math.min(this.pos + offset, this.tokens.length - 1)]; }
  advance() { if (this.pos < this.tokens.length - 1) this.pos += 1; }

  checkSymbol(symbol) {
    return this.current.kind === 'symbol' && this.current.value === symbol;
  }
  checkKeyword(keyword) {
    return this.current.kind === 'keyword' && this.current.value === keyword;
  }

  parseProgram() {
    const statements = [];
    while (this.current.kind !== 'end') {
      statements.push(this.parseStatement());
    }
    return statements;
  }

  // Reads one kind word where an annotation stands. The word
  // arrives as a name token; anything else — or a name that
  // isn't a kind — is refused in plain words. The word 'maybe'
  // may stand before a kind: 'maybe number'.
  parseKindWord(after) {
    if (this.current.kind === 'keyword' && this.current.value === 'nothing') {
      this.advance();
      return 'nothing';
    }
    if (this.current.kind === 'name' && this.current.value === 'maybe') {
      this.advance();
      if (this.current.kind === 'keyword' && this.current.value === 'nothing') {
        throw new NiflaError(this.current.line, "'maybe nothing' says no more than 'nothing' itself — a value that may be nothing or nothing is just nothing. Write 'nothing' alone, or 'maybe' before a real kind, like: maybe number.");
      }
      if (this.current.kind !== 'name') {
        throw new NiflaError(this.current.line, 'After \'maybe\' I need a kind — one of: number, text, boolean, list, object, bytes. Instead I found ' + tokenSpoken(this.current) + '.');
      }
      const inner = this.current.value;
      if (!KIND_WORDS.has(inner)) {
        throw new NiflaError(this.current.line, "I don't know a kind called '" + inner + "'. The kinds a value can be marked as are: number, text, boolean, list, object, bytes, nothing — and 'maybe' can stand before any of them but 'nothing', like: maybe number.");
      }
      this.advance();
      return 'maybe ' + inner;
    }
    if (this.current.kind !== 'name') {
      throw new NiflaError(this.current.line, 'After the ' + after + ' I need a kind — one of: number, text, boolean, list, object, bytes, nothing. Instead I found ' + tokenSpoken(this.current) + '.');
    }
    const word = this.current.value;
    if (!KIND_WORDS.has(word)) {
      throw new NiflaError(this.current.line, "I don't know a kind called '" + word + "'. The kinds a value can be marked as are: number, text, boolean, list, object, bytes, nothing.");
    }
    this.advance();
    return word;
  }

  parseBlock(openLine) {
    const statements = [];
    while (!this.checkSymbol('}')) {
      if (this.current.kind === 'end') {
        throw new NiflaError(openLine, "This '{' is never closed. Add a '}' to finish the block it starts.");
      }
      statements.push(this.parseStatement());
    }
    this.advance(); // the closing '}'
    return statements;
  }

  parseStatement() {
    const token = this.current;

    // A floor block standing on its own: run it for what it
    // does, and let the value it gives back go.
    if (token.kind === 'floor') {
      this.advance();
      return { t: 'doExpr', expr: { t: 'floor', asm: token.value, args: [], line: token.line }, line: token.line };
    }

    // A floor block handed values, standing on its own line.
    if (this.checkKeyword('floor')) {
      const value = this.parseExpression();
      return { t: 'doExpr', expr: value, line: token.line };
    }

    if (this.checkKeyword('let')) {
      this.advance();
      if (this.current.kind !== 'name') {
        throw new NiflaError(this.current.line, "After 'let' I need a name for the new variable, like: let years = 29. Instead I found " + tokenSpoken(this.current) + '.');
      }
      const name = this.current.value;
      this.advance();
      let kind = null;
      if (this.checkSymbol(':')) {
        this.advance();
        kind = this.parseKindWord("':' after 'let " + name + "'");
      }
      if (!this.checkSymbol('=')) {
        throw new NiflaError(this.current.line, "After 'let " + name + "' I need an '=' and then a value, like: let " + name + " = 29. Instead I found " + tokenSpoken(this.current) + '.');
      }
      this.advance();
      const value = this.parseExpression();
      return { t: 'declare', name: name, kind: kind, value: value, line: token.line };
    }

    if (this.checkKeyword('say')) {
      this.advance();
      const value = this.parseExpression();
      return { t: 'say', value: value, line: token.line };
    }

    if (this.checkKeyword('if')) {
      this.advance();
      const condition = this.parseExpression();
      if (!this.checkSymbol('{')) {
        if (this.checkSymbol('=')) {
          throw new NiflaError(this.current.line, "After the 'if' condition I expected '{' but found '='. To compare two things, use '==' — two equals signs. A single '=' sets a variable.");
        }
        throw new NiflaError(this.current.line, "After the 'if' condition I need a '{' to start the block that runs when it's true. Instead I found " + tokenSpoken(this.current) + '.');
      }
      const openLine = this.current.line;
      this.advance();
      const thenBlock = this.parseBlock(openLine);
      let elseBlock = null;
      if (this.checkKeyword('else')) {
        this.advance();
        if (!this.checkSymbol('{')) {
          throw new NiflaError(this.current.line, "After 'else' I need a '{' to start the block that runs when the condition is false. Instead I found " + tokenSpoken(this.current) + '.');
        }
        const elseOpenLine = this.current.line;
        this.advance();
        elseBlock = this.parseBlock(elseOpenLine);
      }
      return { t: 'if', cond: condition, then: thenBlock, otherwise: elseBlock, line: token.line };
    }

    if (this.checkKeyword('while')) {
      this.advance();
      const condition = this.parseExpression();
      if (!this.checkSymbol('{')) {
        if (this.checkSymbol('=')) {
          throw new NiflaError(this.current.line, "After the 'while' condition I expected '{' but found '='. To compare two things, use '==' — two equals signs. A single '=' sets a variable.");
        }
        throw new NiflaError(this.current.line, "After the 'while' condition I need a '{' to start the block that runs again and again while it's true. Instead I found " + tokenSpoken(this.current) + '.');
      }
      const openLine = this.current.line;
      this.advance();
      const body = this.parseBlock(openLine);
      return { t: 'while', cond: condition, body: body, line: token.line };
    }

    if (this.checkKeyword('repeat')) {
      this.advance();
      const count = this.parseExpression();
      if (!this.checkSymbol('{')) {
        throw new NiflaError(this.current.line, "After the 'repeat' count I need a '{' to start the block that runs that many times, like: repeat 3 { ... }. Instead I found " + tokenSpoken(this.current) + '.');
      }
      const openLine = this.current.line;
      this.advance();
      const body = this.parseBlock(openLine);
      return { t: 'repeat', count: count, body: body, line: token.line };
    }

    if (this.checkKeyword('for')) {
      this.advance();
      if (this.current.kind !== 'name') {
        throw new NiflaError(this.current.line, "After 'for' I need a name for each item the loop walks through, like: for item in items { ... }. Instead I found " + tokenSpoken(this.current) + '.');
      }
      const name = this.current.value;
      this.advance();
      if (!this.checkKeyword('in')) {
        throw new NiflaError(this.current.line, "After 'for " + name + "' I need 'in' and then the list or text to walk through, like: for " + name + " in items { ... }. Instead I found " + tokenSpoken(this.current) + '.');
      }
      this.advance();
      const over = this.parseExpression();
      if (!this.checkSymbol('{')) {
        throw new NiflaError(this.current.line, "After 'for " + name + " in ...' I need a '{' to start the block that runs for each item. Instead I found " + tokenSpoken(this.current) + '.');
      }
      const openLine = this.current.line;
      this.advance();
      const body = this.parseBlock(openLine);
      return { t: 'for', name: name, over: over, body: body, line: token.line };
    }

    if (this.checkKeyword('make')) {
      this.advance();
      if (this.current.kind !== 'name') {
        throw new NiflaError(this.current.line, "After 'make' I need a name for the new function, like: make greet(name) { ... }. Instead I found " + tokenSpoken(this.current) + '.');
      }
      const name = this.current.value;
      this.advance();
      if (!this.checkSymbol('(')) {
        throw new NiflaError(this.current.line, "After the function's name I need '(' and the names of the values it takes, like: make " + name + "(name) { ... }. Instead I found " + tokenSpoken(this.current) + '.');
      }
      this.advance(); // the '('
      const params = [];
      const paramKinds = [];
      if (!this.checkSymbol(')')) {
        while (true) {
          if (this.current.kind !== 'name') {
            throw new NiflaError(this.current.line, "Inside the parentheses of 'make " + name + "' I need names for the values, separated by commas, like: make " + name + "(a, b) { ... }. Instead I found " + tokenSpoken(this.current) + '.');
          }
          const param = this.current.value;
          if (params.includes(param)) {
            throw new NiflaError(this.current.line, "The function '" + name + "' uses the name '" + param + "' twice in its list of values. Each value needs its own name.");
          }
          params.push(param);
          this.advance();
          let paramKind = null;
          if (this.checkSymbol(':')) {
            this.advance();
            paramKind = this.parseKindWord("':' after '" + param + "'");
          }
          paramKinds.push(paramKind);
          if (this.checkSymbol(',')) {
            this.advance();
            continue;
          }
          break;
        }
      }
      if (!this.checkSymbol(')')) {
        throw new NiflaError(this.current.line, "I expected a ')' to close the list of values for '" + name + "', but I found " + tokenSpoken(this.current) + '.');
      }
      this.advance(); // the ')'
      let returnKind = null;
      if (this.checkSymbol('->')) {
        this.advance();
        returnKind = this.parseKindWord("'->' in 'make " + name + "'");
      }
      if (!this.checkSymbol('{')) {
        throw new NiflaError(this.current.line, "After 'make " + name + "(...)' I need a '{' to start the block that runs when the function is called. Instead I found " + tokenSpoken(this.current) + '.');
      }
      const openLine = this.current.line;
      this.advance();
      const body = this.parseBlock(openLine);
      return { t: 'define', name: name, params: params, paramKinds: paramKinds, returnKind: returnKind, body: body, line: token.line };
    }

    if (this.checkKeyword('give')) {
      this.advance();
      const value = this.parseExpression();
      return { t: 'give', value: value, line: token.line };
    }

    if (this.checkKeyword('attempt')) {
      this.advance();
      if (!this.checkSymbol('{')) {
        throw new NiflaError(this.current.line, "After 'attempt' I need a '{' to start the block that tries, like: attempt { ... } if it fails { ... }. Instead I found " + tokenSpoken(this.current) + '.');
      }
      const openLine = this.current.line;
      this.advance();
      const body = this.parseBlock(openLine);
      const itToken = this.peekAt(1);
      const failsToken = this.peekAt(2);
      const braceToken = this.peekAt(3);
      let shape = false;
      if (this.checkKeyword('if') &&
          itToken.kind === 'name' && itToken.value === 'it' &&
          failsToken.kind === 'name' && failsToken.value === 'fails' &&
          braceToken.kind === 'symbol' && braceToken.value === '{') {
        shape = true;
      }
      if (!shape) {
        throw new NiflaError(this.current.line, "After an 'attempt' block I need 'if it fails' and a block saying what to do when something goes wrong, like: attempt { ... } if it fails { ... }.");
      }
      this.advance(); // 'if'
      this.advance(); // 'it'
      this.advance(); // 'fails'
      const recoveryOpenLine = this.current.line;
      this.advance(); // '{'
      const recovery = this.parseBlock(recoveryOpenLine);
      return { t: 'attempt', body: body, recovery: recovery, line: token.line };
    }

    // Setting an existing variable: a name followed by '='.
    // Setting a field or an item: a name followed by one or
    // more '.field' or '[...]' steps and then '='.
    // Calling a function for what it does: a name followed
    // by '('.
    if (token.kind === 'name') {
      const name = token.value;
      const next = this.peekAt(1);
      if (next.kind === 'symbol' && next.value === '=') {
        this.advance(); // the name
        this.advance(); // the '='
        const value = this.parseExpression();
        return { t: 'assign', name: name, value: value, line: token.line };
      }
      if (next.kind === 'symbol' && (next.value === '.' || next.value === '[')) {
        this.advance(); // the name
        let target = { t: 'var', name: name, line: token.line };
        while (this.checkSymbol('.') || this.checkSymbol('[')) {
          if (this.checkSymbol('.')) {
            const dotToken = this.current;
            this.advance(); // the '.'
            if (this.current.kind !== 'name') {
              throw new NiflaError(this.current.line, "After '.' I need the name of a field, like: " + name + ".years. Instead I found " + tokenSpoken(this.current) + '.');
            }
            const fieldName = this.current.value;
            this.advance();
            target = { t: 'field', base: target, name: fieldName, line: dotToken.line };
          } else {
            const bracketToken = this.current;
            this.advance(); // the '['
            const indexExpr = this.parseExpression();
            if (!this.checkSymbol(']')) {
              throw new NiflaError(this.current.line, "I expected a ']' to close the '[' from line " + bracketToken.line + ', but I found ' + tokenSpoken(this.current) + '.');
            }
            this.advance(); // the ']'
            target = { t: 'index', base: target, index: indexExpr, line: bracketToken.line };
          }
        }
        if (!this.checkSymbol('=')) {
          throw new NiflaError(this.current.line, "A line that starts with a field or an item like this needs to set it: write an '=' and the new value, like: " + name + ".years = 30 or " + name + "[0] = 30. To show it instead, write it after 'say'.");
        }
        this.advance(); // the '='
        const value = this.parseExpression();
        return { t: 'assignTarget', target: target, value: value, line: token.line };
      }
      if (next.kind === 'symbol' && next.value === '(') {
        this.advance(); // the name
        const args = this.parseCallArgs(name);
        return { t: 'doCall', name: name, args: args, line: token.line };
      }
      throw new NiflaError(token.line, "I found the name '" + name + "' at the start of a line, but a line needs to do something: make a variable with 'let " + name + " = ...', set it with '" + name + " = ...', set a field with '" + name + ".field = ...', set an item with '" + name + "[0] = ...', show it with 'say " + name + "', or call a function with '" + name + "(...)'.");
    }

    throw new NiflaError(token.line, "I expected a line to start with 'let', 'say', 'if', 'while', 'repeat', 'for', 'make', 'give', 'attempt', or the name of a variable to set — but I found " + tokenSpoken(token) + '.');
  }

  // The "( value, value )" part of a call, shared by call
  // statements and calls inside expressions. The current
  // token is the '('.
  parseCallArgs(name) {
    this.advance(); // the '('
    const args = [];
    if (!this.checkSymbol(')')) {
      args.push(this.parseExpression());
      while (this.checkSymbol(',')) {
        this.advance();
        args.push(this.parseExpression());
      }
    }
    if (!this.checkSymbol(')')) {
      throw new NiflaError(this.current.line, "I expected a ')' to close the '(' in this call to '" + name + "', but I found " + tokenSpoken(this.current) + '.');
    }
    this.advance(); // the ')'
    return args;
  }

  parseExpression() { return this.parseEquality(); }

  parseEquality() {
    let left = this.parseComparison();
    while (this.checkSymbol('==') || this.checkSymbol('!=')) {
      const opToken = this.current;
      const op = opToken.value;
      this.advance();
      const right = this.parseComparison();
      left = { t: 'bin', left: left, op: op, right: right, line: opToken.line };
    }
    return left;
  }

  parseComparison() {
    let left = this.parseSum();
    while (this.checkSymbol('<') || this.checkSymbol('<=') || this.checkSymbol('>') || this.checkSymbol('>=')) {
      const opToken = this.current;
      const op = opToken.value;
      this.advance();
      const right = this.parseSum();
      left = { t: 'bin', left: left, op: op, right: right, line: opToken.line };
    }
    return left;
  }

  parseSum() {
    let left = this.parseTerm();
    while (this.checkSymbol('+') || this.checkSymbol('-')) {
      const opToken = this.current;
      const op = opToken.value;
      this.advance();
      const right = this.parseTerm();
      left = { t: 'bin', left: left, op: op, right: right, line: opToken.line };
    }
    return left;
  }

  parseTerm() {
    let left = this.parseFactor();
    while (this.checkSymbol('*') || this.checkSymbol('/')) {
      const opToken = this.current;
      const op = opToken.value;
      this.advance();
      const right = this.parseFactor();
      left = { t: 'bin', left: left, op: op, right: right, line: opToken.line };
    }
    return left;
  }

  parseFactor() {
    if (this.checkSymbol('-')) {
      const opToken = this.current;
      this.advance();
      return { t: 'neg', inner: this.parseFactor(), line: opToken.line };
    }
    return this.parsePostfix();
  }

  // An atom followed by any number of steps: '.field' reads
  // one field of an object, and '[...]' reads one item of a
  // list or one character of some text.
  parsePostfix() {
    let expr = this.parseAtom();
    while (this.checkSymbol('.') || this.checkSymbol('[')) {
      if (this.checkSymbol('.')) {
        const dotToken = this.current;
        this.advance(); // the '.'
        if (this.current.kind !== 'name') {
          throw new NiflaError(this.current.line, "After '.' I need the name of a field, like: person.name. Instead I found " + tokenSpoken(this.current) + '.');
        }
        const fieldName = this.current.value;
        this.advance();
        expr = { t: 'field', base: expr, name: fieldName, line: dotToken.line };
      } else {
        const bracketToken = this.current;
        this.advance(); // the '['
        const indexExpr = this.parseExpression();
        if (!this.checkSymbol(']')) {
          throw new NiflaError(this.current.line, "I expected a ']' to close the '[' from line " + bracketToken.line + ', but I found ' + tokenSpoken(this.current) + '.');
        }
        this.advance(); // the ']'
        expr = { t: 'index', base: expr, index: indexExpr, line: bracketToken.line };
      }
    }
    return expr;
  }

  // A list literal: '[' then values separated by commas, then
  // ']'. A list with nothing in it is '[]'.
  parseListLiteral(openToken) {
    this.advance(); // the '['
    const items = [];
    if (!this.checkSymbol(']')) {
      while (true) {
        items.push(this.parseExpression());
        if (this.checkSymbol(',')) {
          this.advance();
          continue;
        }
        break;
      }
    }
    if (!this.checkSymbol(']')) {
      throw new NiflaError(this.current.line, "I expected a ']' to close the list that started on line " + openToken.line + ', but I found ' + tokenSpoken(this.current) + '.');
    }
    this.advance(); // the ']'
    return { t: 'list', items: items, line: openToken.line };
  }

  // An object literal: '{' then name ':' value pairs
  // separated by commas, then '}'. An object with no fields
  // at all is '{}'.
  parseObjectLiteral(openToken) {
    this.advance(); // the '{'
    const fields = [];
    if (!this.checkSymbol('}')) {
      while (true) {
        if (this.current.kind !== 'name') {
          throw new NiflaError(this.current.line, 'Inside an object I need field names with values, like: { name: "Tyler", years: 29 }. Instead I found ' + tokenSpoken(this.current) + '.');
        }
        const fieldName = this.current.value;
        const fieldLine = this.current.line;
        this.advance();
        if (!this.checkSymbol(':')) {
          throw new NiflaError(this.current.line, "After the field name '" + fieldName + "' I need a ':' and then its value, like: { " + fieldName + ': 29 }. Instead I found ' + tokenSpoken(this.current) + '.');
        }
        this.advance(); // the ':'
        if (fields.some(f => f.name === fieldName)) {
          throw new NiflaError(fieldLine, "This object names the field '" + fieldName + "' twice. Each field needs its own name — take one of the two out.");
        }
        const value = this.parseExpression();
        fields.push({ name: fieldName, value: value });
        if (this.checkSymbol(',')) {
          this.advance();
          continue;
        }
        break;
      }
    }
    if (!this.checkSymbol('}')) {
      throw new NiflaError(this.current.line, "I expected a '}' to close the object that started on line " + openToken.line + ', but I found ' + tokenSpoken(this.current) + '.');
    }
    this.advance(); // the '}'
    return { t: 'object', fields: fields, line: openToken.line };
  }

  parseAtom() {
    const token = this.current;
    switch (token.kind) {
      case 'number':
        this.advance();
        return { t: 'num', v: token.value, line: token.line };
      case 'text':
        this.advance();
        return { t: 'text', v: token.value, line: token.line };
      case 'keyword':
        if (token.value === 'true') { this.advance(); return { t: 'bool', v: true, line: token.line }; }
        if (token.value === 'false') { this.advance(); return { t: 'bool', v: false, line: token.line }; }
        if (token.value === 'nothing') { this.advance(); return { t: 'nothing', line: token.line }; }
        if (token.value === 'floor') {
          // A floor block handed values: the lexer read the
          // values' tokens and captured the block right after
          // them, so what follows the ')' is the block token.
          this.advance();
          const args = this.parseCallArgs('floor');
          if (this.current.kind !== 'floor') {
            throw new NiflaError(this.current.line, "After the values handed to 'floor' I need the block itself: '{' on the same line, then the processor instructions. Instead I found " + tokenSpoken(this.current) + '.');
          }
          const asm = this.current.value;
          this.advance();
          return { t: 'floor', asm: asm, args: args, line: token.line };
        }
        break;
      case 'name': {
        this.advance();
        if (this.checkSymbol('(')) {
          const args = this.parseCallArgs(token.value);
          return { t: 'call', name: token.value, args: args, line: token.line };
        }
        return { t: 'var', name: token.value, line: token.line };
      }
      case 'symbol':
        if (token.value === '(') {
          this.advance();
          const inner = this.parseExpression();
          if (!this.checkSymbol(')')) {
            throw new NiflaError(this.current.line, "I expected a ')' to close the '(' from line " + token.line + ', but I found ' + tokenSpoken(this.current) + '.');
          }
          this.advance();
          return inner;
        }
        if (token.value === '{') return this.parseObjectLiteral(token);
        if (token.value === '[') return this.parseListLiteral(token);
        break;
      case 'floor':
        this.advance();
        return { t: 'floor', asm: token.value, args: [], line: token.line };
    }
    throw new NiflaError(token.line, 'I expected a number, a piece of text, true, false, a variable name, an object like { name: "Tyler" }, a list like [1, 2, 3], or a floor block here, but I found ' + tokenSpoken(token) + '.');
  }
}

// ----------------------------------------------------------------
// The built-in tools, in one place so the interpreter and the
// checker agree on their names and how many values they take.
// `params` names the values, for plain-words messages;
// `example` shows a call.
// ----------------------------------------------------------------

const BUILTIN_TOOLS = {
  length: { params: ['value'], example: 'length("Tyler")' },
  join: { params: ['list', 'separator'], example: 'join(words, " ")' },
  split: { params: ['text', 'separator'], example: 'split("a,b", ",")' },
  part: { params: ['text', 'start', 'count'], example: 'part("Tyler", 0, 2)' },
  find: { params: ['text', 'piece'], example: 'find("Tyler", "y")' },
  append: { params: ['list', 'value'], example: 'append(items, 4)' },
  readfile: { params: ['path'], example: 'readfile("notes.txt")' },
  readbytes: { params: ['path'], example: 'readbytes("notes.txt")' },
  writefile: { params: ['path', 'text'], example: 'writefile("notes.txt", "Shalom")' },
  arguments: { params: [], example: 'arguments()' },
  makebytes: { params: ['count'], example: 'makebytes(8)' },
  sayerr: { params: ['value'], example: 'sayerr("Mind the step.")' },
  exitwith: { params: ['code'], example: 'exitwith(1)' },
  removeat: { params: ['list', 'index'], example: 'removeat(items, 0)' },
  insertat: { params: ['list', 'index', 'value'], example: 'insertat(items, 0, 4)' },
  sorted: { params: ['list'], example: 'sorted(items)' },
  fieldnames: { params: ['object'], example: 'fieldnames(person)' },
  removefield: { params: ['object', 'name'], example: 'removefield(person, "town")' },
  asnumber: { params: ['text'], example: 'asnumber("620")' },
  bitand: { params: ['first', 'second'], example: 'bitand(12, 10)' },
  bitor: { params: ['first', 'second'], example: 'bitor(12, 10)' },
  bitxor: { params: ['first', 'second'], example: 'bitxor(12, 10)' },
  astext: { params: ['bytes'], example: 'astext(block)' },
};

// The plain-words message for a call to a built-in tool with
// the wrong number of values — the same shape as the one for
// functions a program makes itself.
function builtinCountMessage(name, def, given) {
  let takes;
  if (def.params.length === 0) takes = 'no values';
  else if (def.params.length === 1) takes = '1 value (' + def.params[0] + ')';
  else takes = def.params.length + ' values (' + def.params.join(', ') + ')';
  return "The tool '" + name + "' takes " + takes + ', but it was given ' + given + '. Call it like: ' + def.example + '.';
}

// Stone 26: reading a number out of text, the 'asnumber'
// tool's work — the same steps as the Swift mirrors, so
// every door reads the same text to the same number. The
// accepted writing is plain: a '-' first when the number
// is below zero, then digits, then — if a fraction is
// wanted — one '.' and more digits. Anything else, and a
// number too big to hold, come back as null.
function readNumberText(text) {
  const chars = graphemes(text);
  const digit = (ch) => (ch.length === 1 && ch >= '0' && ch <= '9' ? ch.charCodeAt(0) - 48 : null);
  let i = 0;
  let negative = false;
  if (i < chars.length && chars[i] === '-') { negative = true; i += 1; }
  let whole = 0;
  let wholeDigits = 0;
  while (i < chars.length) {
    const d = digit(chars[i]);
    if (d === null) break;
    whole = whole * 10 + d;
    wholeDigits += 1;
    i += 1;
  }
  if (wholeDigits === 0) return null;
  let value = whole;
  if (i < chars.length && chars[i] === '.') {
    i += 1;
    let fraction = 0;
    let scale = 1;
    let fractionDigits = 0;
    while (i < chars.length) {
      const d = digit(chars[i]);
      if (d === null) break;
      fraction = fraction * 10 + d;
      scale *= 10;
      fractionDigits += 1;
      i += 1;
    }
    if (fractionDigits === 0) return null;
    value = whole + fraction / scale;
  }
  if (i !== chars.length) return null;
  const signed = negative ? -value : value;
  if (!Number.isFinite(signed)) return null;
  return signed === 0 ? 0 : signed;
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
function bitToolNumber(value, tool, line) {
  if (typeof value !== 'number') {
    throw new NiflaError(line, "'" + tool + "' needs a whole number to work on, but it was given " + describedOf(value) + '.');
  }
  if (value !== Math.round(value)) {
    throw new NiflaError(line, "'" + tool + "' works on whole numbers — bits are counted in whole numbers — but it was given " + formatNumber(value) + '. Use a whole number, like ' + formatNumber(Math.floor(value)) + ' or ' + formatNumber(Math.ceil(value)) + '.');
  }
  if (value < 0) {
    throw new NiflaError(line, "'" + tool + "' works on whole numbers from zero up — bits below zero have no plain counting — but it was given " + formatNumber(value) + '.');
  }
  if (value > 9007199254740992) {
    throw new NiflaError(line, "'" + tool + "' works on whole numbers up to 9007199254740992, as far as the language's numbers stay exact, but it was given a bigger one.");
  }
  return value;
}

// The bits themselves, counted the same way in every
// mirror: place by place from the ones place up, each
// number halved as its bit is read — the very steps the
// self-made feather checker's 'xorbyte' walks by hand.
// 'keep' says whether a place stands in the answer,
// given the two numbers' bits at that place.
function combineBits(a, b, keep) {
  let x = a;
  let y = b;
  let place = 1;
  let out = 0;
  while (x > 0 || y > 0) {
    const xBit = x % 2;
    const yBit = y % 2;
    if (keep(xBit === 1, yBit === 1)) {
      out += place;
    }
    x = (x - xBit) / 2;
    y = (y - yBit) / 2;
    place *= 2;
  }
  return out;
}

function takesText(params) {
  if (params.length === 0) return 'no values';
  if (params.length === 1) return '1 value (' + params[0] + ')';
  return params.length + ' values (' + params.join(', ') + ')';
}

// ----------------------------------------------------------------
// The checker: a quiet pass over the parsed program that runs
// BEFORE anything is run — the Swift-like safety. It walks the
// program in the order it would run, keeping track of what it
// can prove about each variable's kind, and speaks only when
// it is sure. Where a kind can't be proven, it stays silent
// and the interpreter's own checks remain the guard.
//
// A proven kind is one of the strings 'number', 'text',
// 'boolean', 'object', 'list', 'bytes', 'unknown', 'nothing',
// or { maybe: kind } — a value of that kind, or nothing.
// ----------------------------------------------------------------

function isMaybeKind(kind) {
  return typeof kind === 'object' && kind !== null;
}

function kindEq(a, b) {
  if (a === null || b === null || a === undefined || b === undefined) return false;
  if (isMaybeKind(a) || isMaybeKind(b)) {
    return isMaybeKind(a) && isMaybeKind(b) && kindEq(a.maybe, b.maybe);
  }
  return a === b;
}

function kindPhrase(kind) {
  if (isMaybeKind(kind)) return kindPhrase(kind.maybe) + ' or nothing';
  switch (kind) {
    case 'number': return 'a number';
    case 'text': return 'some text';
    case 'boolean': return 'a true/false value';
    case 'object': return 'an object';
    case 'list': return 'a list';
    case 'bytes': return 'a block of bytes';
    case 'nothing': return 'nothing';
    default: return 'a value';
  }
}

// The kind an annotation word names, or null for 'nothing'
// (a promise checked on its own terms) and for words that
// name no kind.
function fromKindWord(word) {
  if (word.startsWith('maybe ')) {
    const inner = fromKindWord(word.slice('maybe '.length));
    return inner === null ? null : { maybe: inner };
  }
  switch (word) {
    case 'number': case 'text': case 'boolean':
    case 'list': case 'object': case 'bytes':
      return word;
    default: return null;
  }
}

// How an annotation word itself is phrased in a message.
function phraseForKindWord(word) {
  const kind = fromKindWord(word);
  return kind === null ? 'nothing' : kindPhrase(kind);
}

// How two proven kinds join where the program could have gone
// either way (the two sides of an 'if', a loop body against
// the state before it): kinds that agree stay; a definite
// kind meeting the empty value becomes the maybe of that
// kind; anything else that disagrees becomes unknown.
function mergedKind(a, b) {
  if (kindEq(a, b)) return a;
  if (a === 'nothing' && isMaybeKind(b)) return b;
  if (isMaybeKind(a) && b === 'nothing') return a;
  if (a === 'nothing' && b !== 'unknown') return { maybe: b };
  if (b === 'nothing' && a !== 'unknown') return { maybe: a };
  if (isMaybeKind(a) && kindEq(b, a.maybe)) return a;
  if (isMaybeKind(b) && kindEq(a, b.maybe)) return b;
  return 'unknown';
}

// The checker's rules for the built-in tools: the kind a call
// provably gives back, and — for each value the tool takes —
// the kinds that value may have and how the need is phrased
// when a known kind can never work. A null kind set means any
// kind will do.
const BUILTIN_RULES = {
  length: { result: 'number', needs: [{ kinds: ['text', 'list', 'object', 'bytes'], need: 'some text, a list, an object, or a block of bytes to measure' }] },
  join: { result: 'text', needs: [{ kinds: ['list'], need: 'a list to join' }, { kinds: ['text'], need: 'some text to join the items with' }] },
  split: { result: 'list', needs: [{ kinds: ['text'], need: 'some text to split' }, { kinds: ['text'], need: 'some text to split by' }] },
  part: { result: 'text', needs: [{ kinds: ['text'], need: 'some text to take a part of' }, { kinds: ['number'], need: 'a number saying which character to start at' }, { kinds: ['number'], need: 'a number saying how many characters to take' }] },
  find: { result: 'number', needs: [{ kinds: ['text'], need: 'some text to look in' }, { kinds: ['text'], need: 'some text to look for' }] },
  append: { result: 'list', needs: [{ kinds: ['list'], need: 'a list to add to' }, { kinds: null, need: '' }] },
  readfile: { result: 'text', needs: [{ kinds: ['text'], need: 'the name of a file, as text' }] },
  readbytes: { result: 'bytes', needs: [{ kinds: ['text'], need: 'the name of a file, as text' }] },
  writefile: { result: 'number', needs: [{ kinds: ['text'], need: 'the name of a file, as text' }, { kinds: ['text'], need: 'some text to write' }] },
  arguments: { result: 'list', needs: [] },
  makebytes: { result: 'bytes', needs: [{ kinds: ['number'], need: 'a number saying how many bytes to make' }] },
  sayerr: { result: 'number', needs: [{ kinds: null, need: '' }] },
  exitwith: { result: 'unknown', needs: [{ kinds: ['number'], need: 'a whole number from 0 to 255 to end with' }] },
  removeat: { result: 'unknown', needs: [{ kinds: ['list'], need: 'a list to take an item from' }, { kinds: ['number'], need: 'a number saying which item to take out' }] },
  insertat: { result: 'list', needs: [{ kinds: ['list'], need: 'a list to put an item into' }, { kinds: ['number'], need: 'a number saying where to put the new item' }, { kinds: null, need: '' }] },
  sorted: { result: 'list', needs: [{ kinds: ['list'], need: 'a list to sort' }] },
  fieldnames: { result: 'list', needs: [{ kinds: ['object'], need: 'an object to list the field names of' }] },
  removefield: { result: 'unknown', needs: [{ kinds: ['object'], need: 'an object to take a field from' }, { kinds: ['text'], need: 'the name of a field, as text' }] },
  asnumber: { result: 'number', needs: [{ kinds: ['text'], need: 'some text to read a number from' }] },
  bitand: { result: 'number', needs: [{ kinds: ['number'], need: 'a whole number to work on' }, { kinds: ['number'], need: 'a whole number to work on' }] },
  bitor: { result: 'number', needs: [{ kinds: ['number'], need: 'a whole number to work on' }, { kinds: ['number'], need: 'a whole number to work on' }] },
  bitxor: { result: 'number', needs: [{ kinds: ['number'], need: 'a whole number to work on' }, { kinds: ['number'], need: 'a whole number to work on' }] },
  astext: { result: 'text', needs: [{ kinds: ['bytes'], need: 'a block of bytes to read as text' }] },
};

// The checker's picture of the scopes: a stack of blocks,
// each holding the names made in it and the kind proven for
// each — plus, scope by scope beside the kinds, the
// annotation a variable was made with, the constant number
// it provably holds, whether its list is provably empty,
// and the exact length of the list or text it provably
// holds. Facts are held only while they are provable.
class StaticEnv {
  constructor() {
    this.scopes = [new Map()];
    this.annotations = [new Map()];
    this.constants = [new Map()];
    this.emptyLists = [new Map()];
    this.lengths = [new Map()];
  }

  clone() {
    const env = new StaticEnv();
    env.scopes = this.scopes.map(m => new Map(m));
    env.annotations = this.annotations.map(m => new Map(m));
    env.constants = this.constants.map(m => new Map(m));
    env.emptyLists = this.emptyLists.map(m => new Map(m));
    env.lengths = this.lengths.map(m => new Map(m));
    return env;
  }

  lookup(name) {
    for (let i = this.scopes.length - 1; i >= 0; i--) {
      if (this.scopes[i].has(name)) return this.scopes[i].get(name);
    }
    return null;
  }

  lookupAnnotation(name) {
    for (let i = this.annotations.length - 1; i >= 0; i--) {
      if (this.annotations[i].has(name)) return this.annotations[i].get(name);
    }
    return null;
  }

  lookupConstant(name) {
    for (let i = this.constants.length - 1; i >= 0; i--) {
      if (this.constants[i].has(name)) return this.constants[i].get(name);
    }
    return null;
  }

  isProvenEmpty(name) {
    for (let i = this.emptyLists.length - 1; i >= 0; i--) {
      if (this.emptyLists[i].has(name)) return this.emptyLists[i].get(name);
    }
    return false;
  }

  lookupLength(name) {
    for (let i = this.lengths.length - 1; i >= 0; i--) {
      if (this.lengths[i].has(name)) return this.lengths[i].get(name);
    }
    return null;
  }

  isDeclaredHere(name) {
    return this.scopes[this.scopes.length - 1].has(name);
  }

  declare(name, kind, annotation, constant, provenEmpty, length) {
    const i = this.scopes.length - 1;
    this.scopes[i].set(name, kind);
    if (annotation !== null && annotation !== undefined) this.annotations[i].set(name, annotation);
    if (constant !== null && constant !== undefined) this.constants[i].set(name, constant);
    if (provenEmpty) this.emptyLists[i].set(name, true);
    if (length !== null && length !== undefined) this.lengths[i].set(name, length);
  }

  // Sets the kind in whichever block made the name. Returns
  // false when no block knows the name.
  assign(name, kind, constant, provenEmpty, length) {
    for (let i = this.scopes.length - 1; i >= 0; i--) {
      if (this.scopes[i].has(name)) {
        this.scopes[i].set(name, kind);
        if (constant !== null && constant !== undefined) this.constants[i].set(name, constant);
        else this.constants[i].delete(name);
        if (provenEmpty) this.emptyLists[i].set(name, true);
        else this.emptyLists[i].delete(name);
        if (length !== null && length !== undefined) this.lengths[i].set(name, length);
        else this.lengths[i].delete(name);
        return true;
      }
    }
    return false;
  }

  // Sets a name's kind in whichever block made it, and lets
  // its tracked facts go — the narrowing a check against
  // 'nothing' earns.
  narrow(name, to) {
    for (let i = this.scopes.length - 1; i >= 0; i--) {
      if (this.scopes[i].has(name)) {
        this.scopes[i].set(name, to);
        this.constants[i].delete(name);
        this.emptyLists[i].delete(name);
        this.lengths[i].delete(name);
        return;
      }
    }
  }

  // Takes away every tracked fact in every scope, keeping
  // kinds and annotations (used when a function body is
  // checked: inside a body, only facts the body itself
  // establishes are provable).
  dropFacts() {
    this.constants = this.constants.map(() => new Map());
    this.emptyLists = this.emptyLists.map(() => new Map());
    this.lengths = this.lengths.map(() => new Map());
  }

  // Takes away the facts (not the kind, not the annotation)
  // for one name.
  forgetFacts(name) {
    for (let i = this.scopes.length - 1; i >= 0; i--) {
      if (this.scopes[i].has(name)) {
        this.constants[i].delete(name);
        this.emptyLists[i].delete(name);
        this.lengths[i].delete(name);
        return;
      }
    }
  }

  allNames() {
    const names = [];
    for (const scope of this.scopes) {
      for (const name of scope.keys()) names.push(name);
    }
    return names;
  }

  pushScope() {
    this.scopes.push(new Map());
    this.annotations.push(new Map());
    this.constants.push(new Map());
    this.emptyLists.push(new Map());
    this.lengths.push(new Map());
  }

  popScope() {
    this.scopes.pop();
    this.annotations.pop();
    this.constants.pop();
    this.emptyLists.pop();
    this.lengths.pop();
  }

  // After a function call, a function may have set any
  // variable it can reach, to anything. Forget every proven
  // kind and every fact; keep the names, and keep the
  // annotations — they are promises the runtime still
  // guards, not facts the checker proved.
  forgetKinds() {
    for (let i = 0; i < this.scopes.length; i++) {
      for (const name of this.scopes[i].keys()) this.scopes[i].set(name, 'unknown');
      this.constants[i].clear();
      this.emptyLists[i].clear();
      this.lengths[i].clear();
    }
  }

  // Merge two ways the program could have gone: a name keeps
  // its kind only when both ways agree on it; a constant or
  // a length survives only when both ways hold the same one;
  // an empty list only when both ways agree it is still
  // empty.
  static merged(a, b) {
    const result = a.clone();
    const count = Math.min(a.scopes.length, b.scopes.length);
    for (let index = 0; index < count; index++) {
      const scope = new Map();
      const names = new Set([...a.scopes[index].keys(), ...b.scopes[index].keys()]);
      for (const name of names) {
        const kindA = a.scopes[index].has(name) ? a.scopes[index].get(name) : null;
        const kindB = b.scopes[index].has(name) ? b.scopes[index].get(name) : null;
        if (kindA !== null && kindB !== null) scope.set(name, mergedKind(kindA, kindB));
        else if (kindA !== null) scope.set(name, kindA);
        else if (kindB !== null) scope.set(name, kindB);
      }
      result.scopes[index] = scope;
      const anns = new Map();
      for (const name of new Set([...a.annotations[index].keys(), ...b.annotations[index].keys()])) {
        anns.set(name, a.annotations[index].has(name) ? a.annotations[index].get(name) : b.annotations[index].get(name));
      }
      result.annotations[index] = anns;
      const consts = new Map();
      for (const name of new Set([...a.constants[index].keys(), ...b.constants[index].keys()])) {
        if (a.constants[index].has(name) && b.constants[index].has(name) &&
            a.constants[index].get(name) === b.constants[index].get(name)) {
          consts.set(name, a.constants[index].get(name));
        }
      }
      result.constants[index] = consts;
      const empties = new Map();
      for (const name of new Set([...a.emptyLists[index].keys(), ...b.emptyLists[index].keys()])) {
        if (a.emptyLists[index].get(name) === true && b.emptyLists[index].get(name) === true) {
          empties.set(name, true);
        }
      }
      result.emptyLists[index] = empties;
      const lens = new Map();
      for (const name of new Set([...a.lengths[index].keys(), ...b.lengths[index].keys()])) {
        if (a.lengths[index].has(name) && b.lengths[index].has(name) &&
            a.lengths[index].get(name) === b.lengths[index].get(name)) {
          lens.set(name, a.lengths[index].get(name));
        }
      }
      result.lengths[index] = lens;
    }
    return result;
  }
}

class Checker {
  constructor(program) {
    // Every function made anywhere in the program, by name.
    // Collected before checking, so a function can call
    // itself (and a function made later can be called from
    // inside an earlier one's body). When a name is made
    // twice, the first making is the one recorded.
    this.functions = new Map();
    // While a function body is being checked, the promise
    // its 'make' line made about what it gives back.
    this.currentReturnKind = null;
    this.currentFunctionName = null;
    this.collectFunctions(program);
  }

  check(program) {
    let env = new StaticEnv();
    env = this.checkBlock(program, env, new Set());
  }

  collectFunctions(statements) {
    for (const statement of statements) {
      switch (statement.t) {
        case 'define':
          if (!this.functions.has(statement.name)) {
            this.functions.set(statement.name, {
              params: statement.params,
              paramKinds: statement.paramKinds,
              returnKind: statement.returnKind,
            });
          }
          this.collectFunctions(statement.body);
          break;
        case 'attempt':
          this.collectFunctions(statement.body);
          this.collectFunctions(statement.recovery);
          break;
        case 'if':
          this.collectFunctions(statement.then);
          if (statement.otherwise) this.collectFunctions(statement.otherwise);
          break;
        case 'while': case 'repeat': case 'for':
          this.collectFunctions(statement.body);
          break;
        default:
          break;
      }
    }
  }

  // The names 'let' makes directly in a block.
  declaredNames(statements) {
    const names = new Set();
    for (const statement of statements) {
      if (statement.t === 'declare') names.add(statement.name);
    }
    return names;
  }

  checkBlock(statements, env, outerNames) {
    const outer = new Set([...outerNames, ...this.declaredNames(statements)]);
    for (const statement of statements) {
      env = this.checkStatement(statement, env, outer);
    }
    return env;
  }

  // Checks a block that runs as a child scope of the current
  // one (an 'if' side or a loop body), merging what it may
  // have changed on the way out when asked.
  checkChildBlock(statements, env, outerNames, mergeWithBefore) {
    const before = env.clone();
    env.pushScope();
    env = this.checkBlock(statements, env, outerNames);
    env.popScope();
    if (mergeWithBefore) {
      env = StaticEnv.merged(before, env);
    }
    return env;
  }

  checkStatement(statement, env, outerNames) {
    switch (statement.t) {
      case 'declare': {
        const kind = this.checkExpr(statement.value, env, outerNames);
        if (statement.kind !== null) {
          this.checkAnnotation(statement.kind, kind, statement.line,
            "'" + statement.name + "' is marked as " + phraseForKindWord(statement.kind) + ' by its annotation, but this value is ' + kindPhrase(kind) + '. Change the value, or change the annotation.');
        }
        const constant = this.constNumber(statement.value, env);
        const provenEmpty = this.isEmptyListExpr(statement.value, env);
        this.noteAliasing(statement.value, env);
        env.declare(statement.name, this.declaredKind(statement.kind, kind), statement.kind, constant, provenEmpty, this.literalLength(statement.value));
        return env;
      }

      case 'assign': {
        // The interpreter works the value out first, then
        // looks for the variable — so the checker reads in
        // that order.
        const kind = this.checkExpr(statement.value, env, outerNames);
        if (env.lookup(statement.name) === null) {
          throw new NiflaError(statement.line, "I can't set '" + statement.name + "', because no variable called '" + statement.name + "' has been made yet. Make one first with: let " + statement.name + ' = ...');
        }
        const annotation = env.lookupAnnotation(statement.name);
        if (annotation !== null) {
          this.checkAnnotation(annotation, kind, statement.line,
            "'" + statement.name + "' is marked as " + phraseForKindWord(annotation) + ' by its annotation, but this value is ' + kindPhrase(kind) + '. Change the value, or change the annotation.');
        }
        const constant = this.constNumber(statement.value, env);
        const provenEmpty = this.isEmptyListExpr(statement.value, env);
        this.noteAliasing(statement.value, env);
        env.assign(statement.name, this.declaredKind(annotation, kind), constant, provenEmpty, this.literalLength(statement.value));
        return env;
      }

      case 'assignTarget': {
        this.checkExpr(statement.target, env, outerNames);
        this.checkExpr(statement.value, env, outerNames);
        return env;
      }

      case 'say': {
        this.checkExpr(statement.value, env, outerNames);
        return env;
      }

      case 'if': {
        this.checkExpr(statement.cond, env, outerNames);
        // A test against 'nothing' narrows the tested
        // variable on each road (see nothingTest).
        const test = this.nothingTest(statement.cond, env);
        const before = env.clone();
        if (test) env.narrow(test.name, test.thenKind);
        env = this.checkChildBlock(statement.then, env, outerNames, false);
        const afterThen = env;
        env = before;
        if (test) env.narrow(test.name, test.elseKind);
        if (statement.otherwise) {
          env = this.checkChildBlock(statement.otherwise, env, outerNames, false);
        }
        env = StaticEnv.merged(afterThen, env);
        return env;
      }

      case 'while': {
        this.checkExpr(statement.cond, env, outerNames);
        const test = this.nothingTest(statement.cond, env);
        if (test) env.narrow(test.name, test.thenKind);
        env = this.checkChildBlock(statement.body, env, outerNames, true);
        if (test) env.narrow(test.name, test.elseKind);
        return env;
      }

      case 'repeat': {
        const countKind = this.checkExpr(statement.count, env, outerNames);
        this.checkRepeatCount(statement.count, env, statement.line);
        this.checkCountKind(countKind, statement.line);
        env = this.checkChildBlock(statement.body, env, outerNames, true);
        return env;
      }

      case 'for': {
        const overKind = this.checkExpr(statement.over, env, outerNames);
        this.checkWalkKind(overKind, statement.line);
        const before = env.clone();
        env.pushScope();
        env.declare(statement.name, 'unknown');
        env = this.checkBlock(statement.body, env, outerNames);
        env.popScope();
        env = StaticEnv.merged(before, env);
        return env;
      }

      case 'define': {
        this.checkDefine(statement.name, statement.params, statement.paramKinds, statement.returnKind, statement.body, env, outerNames);
        return env;
      }

      case 'give': {
        const kind = this.checkExpr(statement.value, env, outerNames);
        this.checkGive(kind, statement.line);
        return env;
      }

      case 'attempt': {
        // Either block may be the one that runs to the end,
        // so both are checked from the state before, and
        // what follows sees the merge of the two ways. The
        // recovery block also holds 'problem', some text.
        const before = env.clone();
        env = this.checkChildBlock(statement.body, env, outerNames, false);
        const afterBody = env;
        env = before;
        env.pushScope();
        env.declare('problem', 'text');
        env = this.checkBlock(statement.recovery, env, outerNames);
        env.popScope();
        env = StaticEnv.merged(afterBody, env);
        return env;
      }

      case 'doCall': {
        this.checkCall(statement.name, statement.args, statement.line, env, outerNames, false);
        return env;
      }

      case 'doExpr': {
        this.checkExpr(statement.expr, env, outerNames);
        return env;
      }
    }
    return env;
  }

  // A function body is checked where the function is made,
  // in a fresh block inside the scopes around the making,
  // with the values it takes declared there. Names the body
  // uses that aren't in that picture are only called unmade
  // when no 'let' anywhere around the making makes them
  // either — a function is called later, and by then a
  // later 'let' in an enclosing block has run. What the
  // body may have changed is not carried back.
  checkDefine(name, params, paramKinds, returnKind, body, env, outerNames) {
    let bodyEnv = env.clone();
    // Kinds and annotations carry into the body; tracked
    // facts do not.
    bodyEnv.dropFacts();
    bodyEnv.pushScope();
    for (let index = 0; index < params.length; index++) {
      const kindWord = index < paramKinds.length ? paramKinds[index] : null;
      bodyEnv.declare(params[index], this.declaredKind(kindWord, 'unknown'), kindWord);
    }
    const bodyOuter = new Set([...outerNames, ...this.declaredNames(body)]);
    const savedReturnKind = this.currentReturnKind;
    const savedFunctionName = this.currentFunctionName;
    this.currentReturnKind = returnKind;
    this.currentFunctionName = name;
    for (const statement of body) {
      bodyEnv = this.checkStatementInFunction(statement, bodyEnv, bodyOuter);
    }
    this.currentReturnKind = savedReturnKind;
    this.currentFunctionName = savedFunctionName;
  }

  checkStatementInFunction(statement, env, outerNames) {
    if (statement.t === 'define') {
      this.checkDefine(statement.name, statement.params, statement.paramKinds, statement.returnKind, statement.body, env, outerNames);
      return env;
    }
    return this.checkStatementWithForgiveness(statement, env, outerNames);
  }

  // Statements inside a function body are checked like any
  // others, except that a variable name found nowhere is
  // forgiven when a 'let' for it exists in a block around
  // the function's making (it will have run by the time the
  // function is called).
  checkStatementWithForgiveness(statement, env, outerNames) {
    switch (statement.t) {
      case 'declare': {
        const kind = this.checkExprForgiving(statement.value, env, outerNames);
        if (statement.kind !== null) {
          this.checkAnnotation(statement.kind, kind, statement.line,
            "'" + statement.name + "' is marked as " + phraseForKindWord(statement.kind) + ' by its annotation, but this value is ' + kindPhrase(kind) + '. Change the value, or change the annotation.');
        }
        const constant = this.constNumber(statement.value, env);
        const provenEmpty = this.isEmptyListExpr(statement.value, env);
        this.noteAliasing(statement.value, env);
        env.declare(statement.name, this.declaredKind(statement.kind, kind), statement.kind, constant, provenEmpty, this.literalLength(statement.value));
        return env;
      }

      case 'assign': {
        const kind = this.checkExprForgiving(statement.value, env, outerNames);
        if (env.lookup(statement.name) === null && !outerNames.has(statement.name)) {
          throw new NiflaError(statement.line, "I can't set '" + statement.name + "', because no variable called '" + statement.name + "' has been made yet. Make one first with: let " + statement.name + ' = ...');
        }
        const annotation = env.lookupAnnotation(statement.name);
        if (annotation !== null) {
          this.checkAnnotation(annotation, kind, statement.line,
            "'" + statement.name + "' is marked as " + phraseForKindWord(annotation) + ' by its annotation, but this value is ' + kindPhrase(kind) + '. Change the value, or change the annotation.');
        }
        const constant = this.constNumber(statement.value, env);
        const provenEmpty = this.isEmptyListExpr(statement.value, env);
        this.noteAliasing(statement.value, env);
        env.assign(statement.name, this.declaredKind(annotation, kind), constant, provenEmpty, this.literalLength(statement.value));
        return env;
      }

      case 'assignTarget': {
        this.checkExprForgiving(statement.target, env, outerNames);
        this.checkExprForgiving(statement.value, env, outerNames);
        return env;
      }

      case 'say': {
        this.checkExprForgiving(statement.value, env, outerNames);
        return env;
      }

      case 'if': {
        this.checkExprForgiving(statement.cond, env, outerNames);
        const test = this.nothingTest(statement.cond, env);
        const before = env.clone();
        if (test) env.narrow(test.name, test.thenKind);
        env = this.checkChildBlockInFunction(statement.then, env, outerNames);
        const afterThen = env;
        env = before;
        if (test) env.narrow(test.name, test.elseKind);
        if (statement.otherwise) {
          env = this.checkChildBlockInFunction(statement.otherwise, env, outerNames);
        }
        env = StaticEnv.merged(afterThen, env);
        return env;
      }

      case 'while': {
        this.checkExprForgiving(statement.cond, env, outerNames);
        const test = this.nothingTest(statement.cond, env);
        const before = env.clone();
        if (test) env.narrow(test.name, test.thenKind);
        env = this.checkChildBlockInFunction(statement.body, env, outerNames);
        env = StaticEnv.merged(before, env);
        if (test) env.narrow(test.name, test.elseKind);
        return env;
      }

      case 'repeat': {
        const countKind = this.checkExprForgiving(statement.count, env, outerNames);
        this.checkRepeatCount(statement.count, env, statement.line);
        this.checkCountKind(countKind, statement.line);
        const before = env.clone();
        env = this.checkChildBlockInFunction(statement.body, env, outerNames);
        env = StaticEnv.merged(before, env);
        return env;
      }

      case 'for': {
        const overKind = this.checkExprForgiving(statement.over, env, outerNames);
        this.checkWalkKind(overKind, statement.line);
        const before = env.clone();
        env.pushScope();
        env.declare(statement.name, 'unknown');
        const outer = new Set([...outerNames, ...this.declaredNames(statement.body)]);
        for (const inner of statement.body) {
          env = this.checkStatementInFunction(inner, env, outer);
        }
        env.popScope();
        env = StaticEnv.merged(before, env);
        return env;
      }

      case 'define': {
        this.checkDefine(statement.name, statement.params, statement.paramKinds, statement.returnKind, statement.body, env, outerNames);
        return env;
      }

      case 'give': {
        const kind = this.checkExprForgiving(statement.value, env, outerNames);
        this.checkGive(kind, statement.line);
        return env;
      }

      case 'attempt': {
        const before = env.clone();
        env.pushScope();
        const bodyOuter = new Set([...outerNames, ...this.declaredNames(statement.body)]);
        for (const inner of statement.body) {
          env = this.checkStatementInFunction(inner, env, bodyOuter);
        }
        env.popScope();
        const afterBody = env;
        env = before;
        env.pushScope();
        env.declare('problem', 'text');
        const recoveryOuter = new Set([...outerNames, ...this.declaredNames(statement.recovery)]);
        for (const inner of statement.recovery) {
          env = this.checkStatementInFunction(inner, env, recoveryOuter);
        }
        env.popScope();
        env = StaticEnv.merged(afterBody, env);
        return env;
      }

      case 'doCall': {
        this.checkCall(statement.name, statement.args, statement.line, env, outerNames, true);
        return env;
      }

      case 'doExpr': {
        this.checkExprForgiving(statement.expr, env, outerNames);
        return env;
      }
    }
    return env;
  }

  checkChildBlockInFunction(statements, env, outerNames) {
    env.pushScope();
    const outer = new Set([...outerNames, ...this.declaredNames(statements)]);
    for (const statement of statements) {
      env = this.checkStatementInFunction(statement, env, outer);
    }
    env.popScope();
    return env;
  }

  // Checks a call to a built-in tool: the number of values
  // (refused in the run's own words), and each handed value
  // whose kind is proven and can never work for the tool.
  // Returns the kind the tool gives back.
  checkBuiltinCall(name, args, line, env, outerNames, forgiving) {
    const def = BUILTIN_TOOLS[name];
    const rule = BUILTIN_RULES[name];
    const kinds = [];
    for (const arg of args) {
      kinds.push(forgiving ? this.checkExprForgiving(arg, env, outerNames) : this.checkExpr(arg, env, outerNames));
    }
    if (args.length !== def.params.length) {
      throw new NiflaError(line, builtinCountMessage(name, def, args.length));
    }
    for (let index = 0; index < kinds.length; index++) {
      const kind = kinds[index];
      if (kindEq(kind, 'unknown')) continue;
      const need = rule.needs[index];
      if (need.kinds !== null && !need.kinds.some(k => kindEq(k, kind))) {
        let message = "'" + name + "' needs " + need.need + ', but it was given ' + kindPhrase(kind) + '.';
        if (isMaybeKind(kind)) {
          message += " A value that may be nothing has to be checked first: if value == nothing { ... } else { ... } — in the 'else', the value is known to be there.";
        }
        throw new NiflaError(line, message + ' I caught this before the program ran, so nothing ran.');
      }
    }
    // The ranges the checker can prove, and the facts the
    // list tools change.
    this.checkBuiltinRanges(name, args, env, line);
    if (name === 'append' || name === 'insertat' || name === 'removeat') {
      if (args[0].t === 'var') {
        env.forgetFacts(args[0].name);
      }
    }
    return rule.result;
  }

  checkCall(name, args, line, env, outerNames, forgiving) {
    if (BUILTIN_TOOLS[name] !== undefined) {
      this.checkBuiltinCall(name, args, line, env, outerNames, forgiving);
      return;
    }
    // The bare-only tools exist only when a program is being
    // checked for bare metal; on this hosted door those names
    // are simply functions the checker doesn't know.
    const record = this.functions.get(name);
    if (record === undefined) {
      let message = "I don't know a function called '" + name + "' yet. You can make one with: make " + name + '(...) { ... }';
      const suggestion = this.closestFunctionName(name);
      if (suggestion !== null) message += " Did you mean '" + suggestion + "'?";
      throw new NiflaError(line, message);
    }
    const argKinds = [];
    for (const arg of args) {
      argKinds.push(forgiving ? this.checkExprForgiving(arg, env, outerNames) : this.checkExpr(arg, env, outerNames));
    }
    if (args.length !== record.params.length) {
      throw new NiflaError(line, "The function '" + name + "' takes " + takesText(record.params) + ', but it was given ' + args.length + '. Make the call match how the function was made: ' + name + '(' + record.params.join(', ') + ').');
    }
    this.checkCallAnnotations(name, record, argKinds, line);
    env.forgetKinds();
  }

  // Reads an expression and returns the kind it provably has.
  checkExpr(expr, env, outerNames) {
    switch (expr.t) {
      case 'num': return 'number';
      case 'text': return 'text';
      case 'bool': return 'boolean';
      case 'nothing': return 'nothing';

      case 'var': {
        const kind = env.lookup(expr.name);
        if (kind !== null) return kind;
        let message = "I don't know a variable called '" + expr.name + "' yet. You can make one with: let " + expr.name + ' = ...';
        const suggestion = this.closestName(expr.name, env);
        if (suggestion !== null) message += " Did you mean '" + suggestion + "'?";
        throw new NiflaError(expr.line, message);
      }

      case 'call': {
        if (BUILTIN_TOOLS[expr.name] !== undefined) {
          return this.checkBuiltinCall(expr.name, expr.args, expr.line, env, outerNames, false);
        }
        this.checkCall(expr.name, expr.args, expr.line, env, outerNames, false);
        // A function that promised a kind gives that kind
        // provably — its callers can be checked against the
        // promise.
        const record = this.functions.get(expr.name);
        if (record !== undefined && record.returnKind !== null) {
          const kind = fromKindWord(record.returnKind);
          if (kind !== null) return kind;
        }
        return 'unknown';
      }

      case 'object': {
        for (const field of expr.fields) this.checkExpr(field.value, env, outerNames);
        return 'object';
      }

      case 'list': {
        for (const item of expr.items) this.checkExpr(item, env, outerNames);
        return 'list';
      }

      case 'field': {
        const baseKind = this.checkExpr(expr.base, env, outerNames);
        this.checkFieldBase(baseKind, expr.name, expr.line);
        return 'unknown'; // what comes out of an object can't be proven
      }

      case 'index': {
        const baseKind = this.checkExpr(expr.base, env, outerNames);
        const indexKind = this.checkExpr(expr.index, env, outerNames);
        this.checkIndexKind(baseKind, indexKind, expr.line);
        this.checkIndexRange(expr.base, baseKind, expr.index, env, expr.line);
        // A character taken from text is provably text; an
        // item taken from a list could be anything.
        return baseKind === 'text' ? 'text' : 'unknown';
      }

      case 'floor':
        return this.checkFloor(expr.asm, expr.args, expr.line, env, outerNames, false);

      case 'neg': {
        const kind = this.checkExpr(expr.inner, env, outerNames);
        this.checkNegate(kind, expr.line);
        return kind === 'number' ? 'number' : 'unknown';
      }

      case 'bin': {
        const left = this.checkExpr(expr.left, env, outerNames);
        const right = this.checkExpr(expr.right, env, outerNames);
        this.checkDivisor(expr.op, expr.right, env, expr.line);
        return this.checkBinary(expr.op, left, right, expr.line);
      }
    }
    return 'unknown';
  }

  // The same reading, inside a function body: a variable
  // found nowhere is forgiven when a 'let' for it exists
  // around the function's making.
  checkExprForgiving(expr, env, outerNames) {
    switch (expr.t) {
      case 'var': {
        const kind = env.lookup(expr.name);
        if (kind !== null) return kind;
        if (outerNames.has(expr.name)) return 'unknown';
        let message = "I don't know a variable called '" + expr.name + "' yet. You can make one with: let " + expr.name + ' = ...';
        const suggestion = this.closestName(expr.name, env);
        if (suggestion !== null) message += " Did you mean '" + suggestion + "'?";
        throw new NiflaError(expr.line, message);
      }

      case 'call': {
        if (BUILTIN_TOOLS[expr.name] !== undefined) {
          return this.checkBuiltinCall(expr.name, expr.args, expr.line, env, outerNames, true);
        }
        this.checkCall(expr.name, expr.args, expr.line, env, outerNames, true);
        const record = this.functions.get(expr.name);
        if (record !== undefined && record.returnKind !== null) {
          const kind = fromKindWord(record.returnKind);
          if (kind !== null) return kind;
        }
        return 'unknown';
      }

      case 'object': {
        for (const field of expr.fields) this.checkExprForgiving(field.value, env, outerNames);
        return 'object';
      }

      case 'list': {
        for (const item of expr.items) this.checkExprForgiving(item, env, outerNames);
        return 'list';
      }

      case 'field': {
        const baseKind = this.checkExprForgiving(expr.base, env, outerNames);
        this.checkFieldBase(baseKind, expr.name, expr.line);
        return 'unknown';
      }

      case 'index': {
        const baseKind = this.checkExprForgiving(expr.base, env, outerNames);
        const indexKind = this.checkExprForgiving(expr.index, env, outerNames);
        this.checkIndexKind(baseKind, indexKind, expr.line);
        this.checkIndexRange(expr.base, baseKind, expr.index, env, expr.line);
        return baseKind === 'text' ? 'text' : 'unknown';
      }

      case 'floor':
        return this.checkFloor(expr.asm, expr.args, expr.line, env, outerNames, true);

      case 'neg': {
        const kind = this.checkExprForgiving(expr.inner, env, outerNames);
        this.checkNegate(kind, expr.line);
        return kind === 'number' ? 'number' : 'unknown';
      }

      case 'bin': {
        const left = this.checkExprForgiving(expr.left, env, outerNames);
        const right = this.checkExprForgiving(expr.right, env, outerNames);
        this.checkDivisor(expr.op, expr.right, env, expr.line);
        return this.checkBinary(expr.op, left, right, expr.line);
      }

      default:
        return this.checkExpr(expr, env, outerNames);
    }
  }

  // An index whose kind is proven: picking an item of a
  // list, a character of some text, or a byte of a block of
  // bytes takes a number, so a proven kind that isn't a
  // number can never work and is refused before the run.
  checkIndexKind(base, index, line) {
    if (base === 'nothing') {
      throw new NiflaError(line, 'I can\'t take an item from nothing. Only a list or some text has items to take from — like [1, 2, 3], where [0] takes the first item, or "abc", where [0] takes the first character. I caught this before the program ran, so nothing ran.');
    }
    if (isMaybeKind(base)) {
      throw this.unhandledMaybeError(base, line);
    }
    if (index === 'nothing') {
      throw new NiflaError(line, "I can't use nothing to pick an item. Items are picked by a whole number — 0 for the first one, 1 for the second, and so on. I caught this before the program ran, so nothing ran.");
    }
    if (isMaybeKind(index)) {
      throw this.unhandledMaybeError(index, line);
    }
    if (!(base === 'list' || base === 'text' || base === 'bytes')) return;
    if (index === 'unknown' || index === 'number') return;
    throw new NiflaError(line, "I can't use " + kindPhrase(index) + ' to pick an item. Items are picked by a whole number — 0 for the first one, 1 for the second, and so on. I caught this before the program ran, so nothing ran.');
  }

  // Reading a field of the empty value, or of a value that
  // may be it, can never work — only an object has fields.
  checkFieldBase(base, fieldName, line) {
    if (base === 'nothing') {
      throw new NiflaError(line, "I can't read the field '" + fieldName + "' of nothing, because only an object has fields. Make an object first, like: let person = { name: \"Tyler\" } — then person." + fieldName + ' works. I caught this before the program ran, so nothing ran.');
    }
    if (isMaybeKind(base)) {
      throw this.unhandledMaybeError(base, line);
    }
  }

  // A 'repeat' count that is the empty value, or may be it,
  // can never count — in the run's own words.
  checkCountKind(kind, line) {
    if (kind === 'nothing') {
      throw new NiflaError(line, "'repeat' needs a number saying how many times to run, but here it was given nothing. Write it like: repeat 3 { ... } I caught this before the program ran, so nothing ran.");
    }
    if (isMaybeKind(kind)) {
      throw this.unhandledMaybeError(kind, line);
    }
  }

  // A 'for' walk over the empty value, or over a value that
  // may be it, has nothing to walk — in the run's own words.
  checkWalkKind(kind, line) {
    if (kind === 'nothing') {
      throw new NiflaError(line, "'for' needs a list, some text, or a block of bytes to walk through, but here it was given nothing. Write it like: for item in items { ... } I caught this before the program ran, so nothing ran.");
    }
    if (isMaybeKind(kind)) {
      throw this.unhandledMaybeError(kind, line);
    }
  }

  // A minus sign in front of the empty value, or of a value
  // that may be it, can never work.
  checkNegate(kind, line) {
    if (kind === 'nothing') {
      throw new NiflaError(line, 'I can only put a minus sign in front of a number, but here it was in front of nothing. I caught this before the program ran, so nothing ran.');
    }
    if (isMaybeKind(kind)) {
      throw this.unhandledMaybeError(kind, line);
    }
  }

  // When a condition tests a 'maybe' variable against
  // 'nothing', the two roads know more than the variable's
  // kind alone says: on the road where the test held, the
  // variable is the empty value (for '==') or the kind
  // itself (for '!='); on the other road, the opposite.
  // Returns the variable's name and the kind each road may
  // narrow it to, or null when the condition has another
  // shape — narrowing is earned only by this plain test.
  nothingTest(condition, env) {
    if (condition.t !== 'bin' || (condition.op !== '==' && condition.op !== '!=')) return null;
    const sides = [[condition.left, condition.right], [condition.right, condition.left]];
    for (const [varSide, otherSide] of sides) {
      if (varSide.t !== 'var') continue;
      const name = varSide.name;
      const kind = env.lookup(name);
      if (kind === null) continue;
      // The maybe the variable answers to: its proven kind,
      // when that is a maybe — or its annotation, when the
      // value it provably holds right now is one of the
      // maybe's two roads.
      let inner = null;
      if (isMaybeKind(kind)) {
        inner = kind.maybe;
      } else {
        const word = env.lookupAnnotation(name);
        if (word !== null) {
          const marked = fromKindWord(word);
          if (marked !== null && isMaybeKind(marked) && (kindEq(kind, 'nothing') || kindEq(kind, marked.maybe))) {
            inner = marked.maybe;
          }
        }
      }
      if (inner === null) continue;
      let otherIsNothing = false;
      if (otherSide.t === 'nothing') {
        otherIsNothing = true;
      } else if (otherSide.t === 'var' && kindEq(env.lookup(otherSide.name), 'nothing')) {
        otherIsNothing = true;
      }
      if (!otherIsNothing) continue;
      if (condition.op === '==') {
        return { name: name, thenKind: 'nothing', elseKind: inner };
      }
      return { name: name, thenKind: inner, elseKind: 'nothing' };
    }
    return null;
  }

  // The kind a name is recorded under: an annotation's kind
  // when there is one, otherwise the kind the value was
  // proven to have. A proven kind that satisfies the
  // annotation is the more precise record, and is kept. A
  // 'nothing' mark records the empty kind itself.
  declaredKind(kindWord, proven) {
    if (kindWord === null || kindWord === undefined) return proven;
    if (kindWord === 'nothing') return 'nothing';
    const wanted = fromKindWord(kindWord);
    if (wanted === null) return 'unknown';
    if (!kindEq(proven, 'unknown') && this.annotationSatisfied(proven, wanted)) {
      return proven;
    }
    return wanted;
  }

  // Whether a proven kind satisfies an annotation's kind —
  // the kind itself, or, for a 'maybe' mark, the kind it
  // names or the empty value.
  annotationSatisfied(proven, wanted) {
    if (kindEq(proven, wanted)) return true;
    if (isMaybeKind(wanted)) {
      return kindEq(proven, wanted.maybe) || proven === 'nothing';
    }
    return false;
  }

  // The refusal for a use of a value that may be nothing,
  // where a value that is surely there is needed.
  unhandledMaybeError(kind, line) {
    return new NiflaError(line, 'This uses ' + kindPhrase(kind) + ' — a value that may be nothing — where a value that is surely there is needed, and nothing is the empty value: there is nothing there to use. Check the value first, like: if value == nothing { ... } else { ... } — in the \'else\', the value is known to be there. I caught this before the program ran, so nothing ran.');
  }

  // Refuses when a proven kind can never satisfy an
  // annotation. Stays silent when the kind can't be proven —
  // the runtime guard at the boundary is the keeper there.
  checkAnnotation(kindWord, proven, line, wording) {
    if (kindWord === 'nothing') {
      if (!kindEq(proven, 'unknown') && proven !== 'nothing') {
        throw new NiflaError(line, wording + ' I caught this before the program ran, so nothing ran.');
      }
      return;
    }
    const wanted = fromKindWord(kindWord);
    if (wanted === null) return;
    if (!kindEq(proven, 'unknown') && !this.annotationSatisfied(proven, wanted)) {
      throw new NiflaError(line, wording + ' I caught this before the program ran, so nothing ran.');
    }
  }

  // The annotation check at a call: each handed value whose
  // kind is proven against the parameter it lands in.
  checkCallAnnotations(name, record, argKinds, line) {
    for (let index = 0; index < record.paramKinds.length; index++) {
      const kindWord = record.paramKinds[index];
      if (kindWord === null || kindWord === undefined || index >= argKinds.length) continue;
      const proven = argKinds[index];
      if (kindEq(proven, 'unknown')) continue;
      this.checkAnnotation(kindWord, proven, line,
        "The value handed to '" + name + "' for '" + record.params[index] + "' is " + kindPhrase(proven) + ", but '" + record.params[index] + "' is marked as " + phraseForKindWord(kindWord) + ' by its annotation. Change what the call hands over, or change the annotation.');
    }
  }

  // The annotation check at a 'give': the value handed back,
  // against the promise on the function's 'make' line.
  checkGive(kind, line) {
    if (this.currentReturnKind === null || this.currentFunctionName === null) return;
    this.checkAnnotation(this.currentReturnKind, kind, line,
      "'" + this.currentFunctionName + "' is marked to give back " + phraseForKindWord(this.currentReturnKind) + " by its annotation, but this 'give' hands back " + kindPhrase(kind) + '. Change the value, or change the annotation.');
  }

  // A 'repeat' count the checker can prove is negative.
  checkRepeatCount(count, env, line) {
    const value = this.constNumber(count, env);
    if (value !== null && value < 0) {
      throw new NiflaError(line, "'repeat' was told to run " + formatNumber(value) + " times, but a count can't be negative — a loop can't run less than zero times. Use zero or more, like: repeat 3 { ... } I caught this before the program ran, so nothing ran.");
    }
  }

  // A division whose second number the checker can prove is
  // zero. (Nifla has no modulo sign; '/' is the only divisor.)
  checkDivisor(op, right, env, line) {
    if (op !== '/') return;
    const value = this.constNumber(right, env);
    if (value !== null && value === 0) {
      throw new NiflaError(line, "I can't divide by zero. Dividing needs a second number that isn't zero. I caught this before the program ran, so nothing ran.");
    }
  }

  // An index the checker can prove lands outside: a literal
  // text or list carries its length on its face; a list
  // variable proven empty refuses any index; a negative
  // whole index can never pick from anything.
  checkIndexRange(base, baseKind, index, env, line) {
    const raw = this.constNumber(index, env);
    const whole = (raw !== null && raw === Math.round(raw) && Math.abs(raw) < 1e15) ? Math.trunc(raw) : null;
    const suffix = ' I caught this before the program ran, so nothing ran.';
    if (base.t === 'text') {
      const length = graphemeCount(base.v);
      if (length === 0) {
        if (whole !== null) {
          throw new NiflaError(line, 'This text has no characters yet, so there is no character ' + whole + ' to take from it.' + suffix);
        }
        throw new NiflaError(line, 'This text is empty — it has no characters — so no number can pick a character from it.' + suffix);
      }
      if (whole !== null && (whole < 0 || whole >= length)) {
        throw new NiflaError(line, 'This text has ' + length + ' characters, numbered 0 to ' + (length - 1) + ', but I was asked for character ' + whole + ').' + suffix);
      }
      return;
    }
    if (base.t === 'list') {
      if (base.items.length === 0) {
        if (whole !== null) {
          throw new NiflaError(line, 'This list has no items yet, so there is no item ' + whole + ' to take from it. Items can be added with append — like: append(items, ...).' + suffix);
        }
        throw new NiflaError(line, 'This list is empty — it has no items — so no number can pick an item from it. Items can be added with append — like: append(items, ...).' + suffix);
      }
      if (whole !== null && (whole < 0 || whole >= base.items.length)) {
        throw new NiflaError(line, 'This list has ' + base.items.length + ' items, numbered 0 to ' + (base.items.length - 1) + ', but I was asked for item ' + whole + ').' + suffix);
      }
      return;
    }
    if (base.t === 'var' && baseKind === 'list' && env.isProvenEmpty(base.name)) {
      if (whole !== null) {
        throw new NiflaError(line, 'This list has no items yet, so there is no item ' + whole + ' to take from it. Items can be added with append — like: append(items, ...).' + suffix);
      }
      throw new NiflaError(line, 'This list is empty — it has no items — so no number can pick an item from it. Items can be added with append — like: append(items, ...).' + suffix);
    }
    // A variable whose list or text length is tracked (it
    // was made from a literal of that length and nothing
    // provably changed it since).
    if (base.t === 'var') {
      const length = env.lookupLength(base.name);
      if (length !== null && (baseKind === 'list' || baseKind === 'text')) {
        if (length === 0) {
          if (baseKind === 'text') {
            if (whole !== null) {
              throw new NiflaError(line, 'This text has no characters yet, so there is no character ' + whole + ' to take from it.' + suffix);
            }
            throw new NiflaError(line, 'This text is empty — it has no characters — so no number can pick a character from it.' + suffix);
          }
          if (whole !== null) {
            throw new NiflaError(line, 'This list has no items yet, so there is no item ' + whole + ' to take from it. Items can be added with append — like: append(items, ...).' + suffix);
          }
          throw new NiflaError(line, 'This list is empty — it has no items — so no number can pick an item from it. Items can be added with append — like: append(items, ...).' + suffix);
        }
        if (whole !== null && (whole < 0 || whole >= length)) {
          if (baseKind === 'text') {
            throw new NiflaError(line, 'This text has ' + length + ' characters, numbered 0 to ' + (length - 1) + ', but I was asked for character ' + whole + ').' + suffix);
          }
          throw new NiflaError(line, 'This list has ' + length + ' items, numbered 0 to ' + (length - 1) + ', but I was asked for item ' + whole + ').' + suffix);
        }
        return;
      }
    }
    if (whole !== null && whole < 0 && (baseKind === 'list' || baseKind === 'text' || baseKind === 'bytes')) {
      throw new NiflaError(line, 'Items are numbered starting at 0, so item ' + whole + ' can never be taken — there is nothing before the first one.' + suffix);
    }
  }

  // The ranges of the built-in tools that the checker can
  // prove from literals and tracked facts: makebytes'
  // count, exitwith's parting number, removeat on a list
  // proven empty or of literal length, and part's span over
  // a literal text. Each refusal speaks in the run's own
  // words.
  checkBuiltinRanges(name, args, env, line) {
    const suffix = ' I caught this before the program ran, so nothing ran.';
    switch (name) {
      case 'makebytes': {
        if (args.length !== 1) return;
        const value = this.constNumber(args[0], env);
        if (value === null) return;
        if (value < 0) {
          throw new NiflaError(line, "'makebytes' was told to make " + formatNumber(value) + " bytes, but a count can't be less than 0." + suffix);
        }
        if (value > 16777216) {
          throw new NiflaError(line, "'makebytes' was told to make " + formatNumber(value) + ' bytes, but one block can hold at most 16777216 bytes.' + suffix);
        }
        return;
      }
      case 'exitwith': {
        if (args.length !== 1) return;
        const value = this.constNumber(args[0], env);
        if (value === null) return;
        if (value !== Math.round(value) || value < 0 || value > 255) {
          throw new NiflaError(line, "'exitwith' needs a whole number from 0 to 255, but it was given " + formatNumber(value) + '.' + suffix);
        }
        return;
      }
      case 'removeat': {
        if (args.length !== 2) return;
        const raw = this.constNumber(args[1], env);
        const whole = (raw !== null && raw === Math.round(raw) && Math.abs(raw) < 1e15) ? Math.trunc(raw) : null;
        let length = null;
        let provenEmpty = false;
        if (args[0].t === 'list') {
          length = args[0].items.length;
          provenEmpty = args[0].items.length === 0;
        } else if (args[0].t === 'var') {
          provenEmpty = env.isProvenEmpty(args[0].name);
          length = env.lookupLength(args[0].name);
        }
        if (provenEmpty) {
          if (whole !== null) {
            throw new NiflaError(line, 'This list has no items yet, so there is no item ' + whole + ' to remove.' + suffix);
          }
          throw new NiflaError(line, 'This list is empty — it has no items — so there is no item to remove from it.' + suffix);
        }
        if (length !== null && whole !== null && (whole < 0 || whole >= length)) {
          throw new NiflaError(line, 'This list has ' + length + ' items, numbered 0 to ' + (length - 1) + ', but I was asked to remove item ' + whole + ').' + suffix);
        }
        return;
      }
      case 'part': {
        if (args.length !== 3 || args[0].t !== 'text') return;
        const length = graphemeCount(args[0].v);
        const toWhole = (expr) => {
          const v = this.constNumber(expr, env);
          return (v !== null && v === Math.round(v) && Math.abs(v) < 1e15) ? Math.trunc(v) : null;
        };
        const start = toWhole(args[1]);
        const count = toWhole(args[2]);
        if (start !== null && start < 0) {
          throw new NiflaError(line, "'part' was told to start at character " + start + ", but the first character is number 0 — a start can't be less than 0." + suffix);
        }
        if (count !== null && count < 0) {
          throw new NiflaError(line, "'part' was told to take " + count + " characters, but a count can't be less than 0." + suffix);
        }
        if (start !== null && start > length) {
          if (length === 0) {
            throw new NiflaError(line, "'part' was told to start at character " + start + ', but the text has no characters yet.' + suffix);
          }
          throw new NiflaError(line, "'part' was told to start at character " + start + ', but the text has only ' + length + ' characters, numbered 0 to ' + (length - 1) + ').' + suffix);
        }
        if (start !== null && count !== null && length > 0 && start + count > length) {
          throw new NiflaError(line, "'part' was told to take " + count + ' characters starting at character ' + start + ', but the text has only ' + length + ' characters, numbered 0 to ' + (length - 1) + ' — that runs past the end.' + suffix);
        }
        return;
      }
      default:
        return;
    }
  }

  // The number an expression provably holds, from literals
  // and simple tracked facts only: a literal, the negative
  // of one, a variable whose constant is tracked, and plain
  // arithmetic over those. Anything else proves nothing,
  // and this stays silent (null).
  constNumber(expr, env) {
    switch (expr.t) {
      case 'num':
        return expr.v;
      case 'neg': {
        const inner = this.constNumber(expr.inner, env);
        return inner === null ? null : -inner;
      }
      case 'var':
        return env.lookupConstant(expr.name);
      case 'bin': {
        const a = this.constNumber(expr.left, env);
        const b = this.constNumber(expr.right, env);
        if (a === null || b === null) return null;
        switch (expr.op) {
          case '+': return a + b;
          case '-': return a - b;
          case '*': return a * b;
          case '/': return b === 0 ? null : a / b;
          default: return null;
        }
      }
      default:
        return null;
    }
  }

  // The length an expression provably holds, when it is a
  // literal list or text: the length is on its face.
  literalLength(expr) {
    switch (expr.t) {
      case 'list': return expr.items.length;
      case 'text': return graphemeCount(expr.v);
      default: return null;
    }
  }

  // Whether an expression provably holds an empty list: the
  // empty list itself, or a variable tracked as holding one.
  isEmptyListExpr(expr, env) {
    switch (expr.t) {
      case 'list': return expr.items.length === 0;
      case 'var': return env.isProvenEmpty(expr.name);
      default: return false;
    }
  }

  // A list value handed on — into a new variable, by a 'let'
  // or a set — is the same list under two names, and the new
  // name could grow it where the checker can't watch. The
  // old name's facts are given up.
  noteAliasing(expr, env) {
    if (expr.t === 'var') {
      env.forgetFacts(expr.name);
    }
  }

  // A floor block: the checker treats the instructions as
  // opaque, but it does verify the block isn't empty, and it
  // checks the values the block is handed: each must be a
  // number or a block of bytes, and there may be only one
  // block of bytes. What a block gives back can no longer be
  // proven, so the kind is unknown. (On this hosted door the
  // run refuses floor code in any case, before anything
  // runs — see the interpreter.)
  checkFloor(asm, args, line, env, outerNames, forgiving) {
    if (asm.trim() === '') {
      throw new NiflaError(line, "This floor block is empty — it needs the processor instructions it is meant to run, between the 'floor {' line and the line holding only '}'.");
    }
    let bytesSeen = 0;
    for (const arg of args) {
      const kind = forgiving ? this.checkExprForgiving(arg, env, outerNames) : this.checkExpr(arg, env, outerNames);
      if (kindEq(kind, 'bytes')) {
        bytesSeen += 1;
        if (bytesSeen > 1) {
          throw new NiflaError(line, "'floor' can be handed only one block of bytes, but it was given two. I caught this before the program ran, so nothing ran.");
        }
      } else if (!kindEq(kind, 'unknown') && !kindEq(kind, 'number')) {
        throw new NiflaError(line, "'floor' can be handed numbers and one block of bytes, but it was given " + kindPhrase(kind) + '. I caught this before the program ran, so nothing ran.');
      }
    }
    return 'unknown';
  }

  // The kind rules of the operators, mirroring the
  // interpreter's own: the checker speaks only when BOTH
  // sides' kinds are known and the pairing can never work.
  // ('==' and '!=' never fail — different kinds are simply
  // unequal — so they are never flagged.)
  checkBinary(op, left, right, line) {
    // The empty value, and values that may be it. Equality
    // is how a maybe is checked, so '==' and '!=' are always
    // allowed. Text joining is the other safe road: '+' with
    // text on either side joins anything. Every other use
    // of a proven nothing is refused in the run's own words;
    // every other use of a maybe is refused as an unhandled
    // maybe.
    if (op !== '==' && op !== '!=') {
      const leftMaybe = isMaybeKind(left), rightMaybe = isMaybeKind(right);
      if (leftMaybe || rightMaybe) {
        if (op === '+' && (left === 'text' || right === 'text')) {
          return 'text';
        }
        throw this.unhandledMaybeError(leftMaybe ? left : right, line);
      }
      if (left === 'nothing' || right === 'nothing') {
        if (op === '+' && (left === 'text' || right === 'text')) {
          return 'text';
        }
        const note = ' Nothing is the empty value: there is nothing there to work with. If a value might be nothing, check it first — if value == nothing { ... } else { ... } — and use it in the \'else\', where it is known to be there.';
        switch (op) {
          case '+':
            throw new NiflaError(line, "I can't add " + kindPhrase(left) + ' and ' + kindPhrase(right) + ". '+' adds two numbers, or joins text together." + note + ' I caught this before the program ran, so nothing ran.');
          case '-': case '*': case '/': {
            const verb = op === '-' ? 'subtract' : (op === '*' ? 'multiply' : 'divide');
            throw new NiflaError(line, "I can't " + verb + ' ' + kindPhrase(left) + ' and ' + kindPhrase(right) + ". '" + op + "' works on two numbers. (Only '+' joins text.)" + note + ' I caught this before the program ran, so nothing ran.');
          }
          case '<': case '<=': case '>': case '>=':
            throw new NiflaError(line, "I can't compare " + kindPhrase(left) + ' and ' + kindPhrase(right) + " with '" + op + "'. '" + op + "' compares two numbers. (Text and true/false values can be checked with == and !=.)" + note + ' I caught this before the program ran, so nothing ran.');
          default:
            break;
        }
      }
    }
    switch (op) {
      case '+':
        if (!kindEq(left, 'unknown') && !kindEq(right, 'unknown')) {
          if (left === 'text' || right === 'text') return 'text';
          if (left === 'number' && right === 'number') return 'number';
          throw new NiflaError(line, "I can't add " + kindPhrase(left) + ' and ' + kindPhrase(right) + ". '+' adds two numbers, or joins text together. I caught this before the program ran, so nothing ran.");
        }
        if (left === 'text' || right === 'text') return 'text';
        return 'unknown';

      case '-': case '*': case '/':
        if (!kindEq(left, 'unknown') && !kindEq(right, 'unknown')) {
          if (!(left === 'number' && right === 'number')) {
            const verb = op === '-' ? 'subtract' : (op === '*' ? 'multiply' : 'divide');
            throw new NiflaError(line, "I can't " + verb + ' ' + kindPhrase(left) + ' and ' + kindPhrase(right) + ". '" + op + "' works on two numbers. (Only '+' joins text.) I caught this before the program ran, so nothing ran.");
          }
          return 'number';
        }
        return 'number';

      case '<': case '<=': case '>': case '>=':
        if (!kindEq(left, 'unknown') && !kindEq(right, 'unknown')) {
          if (!(left === 'number' && right === 'number')) {
            throw new NiflaError(line, "I can't compare " + kindPhrase(left) + ' and ' + kindPhrase(right) + " with '" + op + "'. '" + op + "' compares two numbers. (Text and true/false values can be checked with == and !=.) I caught this before the program ran, so nothing ran.");
          }
        }
        return 'boolean';

      case '==': case '!=':
        return 'boolean';

      default:
        return 'unknown';
    }
  }

  closestFunctionName(to) {
    let best = null;
    const candidates = [...this.functions.keys()].sort(compareText);
    for (const candidate of candidates) {
      if (candidate === to) continue;
      const distance = editDistance(to, candidate);
      if (distance <= 2 && (best === null || distance < best.distance)) {
        best = { name: candidate, distance: distance };
      }
    }
    return best === null ? null : best.name;
  }

  closestName(to, env) {
    let best = null;
    const candidates = [...new Set(env.allNames())].sort(compareText);
    for (const candidate of candidates) {
      if (candidate === to) continue;
      const distance = editDistance(to, candidate);
      if (distance <= 2 && (best === null || distance < best.distance)) {
        best = { name: candidate, distance: distance };
      }
    }
    return best === null ? null : best.name;
  }
}

// ----------------------------------------------------------------
// The interpreter: walks the parser's tree and runs it.
//
// A Nifla value is a plain JavaScript value where one fits —
// a number is a number, text is a string, true/false are
// booleans — and a small class where it doesn't: objects,
// lists, and blocks of bytes are shared by reference, the
// way JavaScript's own are, so they are classes; the empty
// value, 'nothing', is one frozen marker, NOTHING.
// ----------------------------------------------------------------

const NOTHING = Object.freeze({ niflaNothing: true });

// An object: named fields, kept in the order they were first
// written.
class NObject {
  constructor() {
    this.fieldNames = [];
    this.values = new Map();
  }
  // Sets a field: an existing field keeps its place in the
  // order; a new one is added at the end.
  set(name, value) {
    if (!this.values.has(name)) this.fieldNames.push(name);
    this.values.set(name, value);
  }
  // Takes a field out: hands back the value it held, or
  // undefined when the object has no such field.
  remove(name) {
    if (!this.values.has(name)) return undefined;
    const value = this.values.get(name);
    this.values.delete(name);
    this.fieldNames.splice(this.fieldNames.indexOf(name), 1);
    return value;
  }
}

// A list: values in order.
class NList {
  constructor(items) { this.items = items || []; }
}

// A block of bytes: raw memory, a fixed number of bytes,
// each a whole number from 0 to 255. Its size is set when it
// is made and never changes.
class NBytes {
  constructor(count) { this.data = new Uint8Array(count); }
}

function kindOf(value) {
  if (value === NOTHING) return 'nothing';
  if (typeof value === 'number') return 'number';
  if (typeof value === 'string') return 'text';
  if (typeof value === 'boolean') return 'boolean';
  if (value instanceof NObject) return 'object';
  if (value instanceof NList) return 'list';
  if (value instanceof NBytes) return 'bytes';
  return 'unknown';
}

// How a value is shown by `say`. An object is shown as a
// readable listing of its fields — { name: "Tyler", years: 29 }
// — with text values in quotes inside a listing, and nested
// objects listed the same way. `seen` holds the objects
// already being listed on the way here, so an object that
// contains itself stops at "..." instead of listing forever.
function renderValue(value, seen, quoted) {
  switch (kindOf(value)) {
    case 'number': return formatNumber(value);
    case 'text': return quoted ? '"' + value + '"' : value;
    case 'boolean': return value ? 'true' : 'false';
    case 'object': {
      if (seen.has(value)) return '...';
      if (value.fieldNames.length === 0) return '{ }';
      const inner = new Set(seen);
      inner.add(value);
      const parts = value.fieldNames.map(name => name + ': ' + renderValue(value.values.get(name), inner, true));
      return '{ ' + parts.join(', ') + ' }';
    }
    case 'list': {
      if (seen.has(value)) return '...';
      if (value.items.length === 0) return '[]';
      const inner = new Set(seen);
      inner.add(value);
      const parts = value.items.map(item => renderValue(item, inner, true));
      return '[' + parts.join(', ') + ']';
    }
    case 'bytes': {
      const parts = [...value.data].map(n => String(n));
      return 'bytes(' + parts.join(', ') + ')';
    }
    default: return 'nothing';
  }
}

function spokenOf(value) {
  return renderValue(value, new Set(), false);
}

// How a value is described inside an error message.
function describedOf(value) {
  switch (kindOf(value)) {
    case 'number': return 'the number ' + formatNumber(value);
    case 'text': return 'the text "' + value + '"';
    case 'boolean': return value ? 'true' : 'false';
    case 'object':
      if (value.fieldNames.length === 0) return 'an object with no fields yet';
      return 'an object with the fields ' + value.fieldNames.join(', ');
    case 'list':
      if (value.items.length === 0) return 'an empty list';
      if (value.items.length === 1) return 'a list of 1 item';
      return 'a list of ' + value.items.length + ' items';
    case 'bytes':
      if (value.data.length === 0) return 'an empty block of bytes';
      if (value.data.length === 1) return 'a block of 1 byte';
      return 'a block of ' + value.data.length + ' bytes';
    default: return 'nothing';
  }
}

// Whether a value (or the lack of one, from a function that
// gave nothing back — undefined here) satisfies an
// annotation.
function kindSatisfies(kindWord, value) {
  if (kindWord === 'nothing') {
    if (value === undefined) return true;
    return value === NOTHING;
  }
  if (kindWord.startsWith('maybe ')) {
    if (value === undefined) return true;
    if (value === NOTHING) return true;
    return kindOf(value) === kindWord.slice('maybe '.length);
  }
  if (value === undefined) return false;
  return kindOf(value) === kindWord;
}

// The words that follow an operation's refusal when one side
// was the empty value — why it failed, and the shape that
// works. The checker speaks the same words (before the run,
// with its own closing line added).
const NOTHING_NOTE = " Nothing is the empty value: there is nothing there to work with. If a value might be nothing, check it first — if value == nothing { ... } else { ... } — and use it in the 'else', where it is known to be there.";

// Floor code runs on the floor desk — see its own section
// below, after the interpreter.

// One scope of variables. Blocks get their own scope, linked
// to the scope around them; a variable made inside a block
// stays inside it. (A stored value is never undefined, so
// undefined from a lookup means "no such variable".)
class Scope {
  constructor(parent) {
    this.values = new Map();
    // The kind annotation a variable in this scope was made
    // with, if any — the runtime guard's memory of the
    // promise, consulted whenever the variable is set.
    this.annotations = new Map();
    this.parent = parent || null;
  }
  lookup(name) {
    if (this.values.has(name)) return this.values.get(name);
    return this.parent ? this.parent.lookup(name) : undefined;
  }
  declareAnnotation(name, kindWord) { this.annotations.set(name, kindWord); }
  annotation(name) {
    if (this.annotations.has(name)) return this.annotations.get(name);
    return this.parent ? this.parent.annotation(name) : null;
  }
  isDeclaredHere(name) { return this.values.has(name); }
  declare(name, value) { this.values.set(name, value); }
  // Sets the variable in whichever scope made it. Returns
  // false when no scope knows the name.
  assign(name, value) {
    if (this.values.has(name)) {
      this.values.set(name, value);
      return true;
    }
    return this.parent ? this.parent.assign(name, value) : false;
  }
  // Every name visible from here, for "did you mean"
  // suggestions.
  allNames() {
    const names = [...this.values.keys()];
    return this.parent ? names.concat(this.parent.allNames()) : names;
  }
}

class Interpreter {
  constructor(store, args) {
    // The runaway guard: a kindness limit on the total
    // number of loop passes in one run, across every loop
    // in the program.
    this.loopPasses = 0;
    this.loopPassLimit = 1000000;
    // The call-depth guard: how many calls are running at
    // once, one inside another.
    this.callDepth = 0;
    this.callDepthLimit = 500;
    // The words handed to the program when it was started —
    // what arguments() gives.
    this.programArguments = args;
    // The functions this run has made, by name.
    this.functions = new Map();
    // The paper-store: a Map from a file's name to its
    // contents (text, or a Uint8Array of bytes).
    this.store = store;
    this.output = '';
    this.errorOutput = '';
  }

  tickLoop(line) {
    this.loopPasses += 1;
    if (this.loopPasses > this.loopPassLimit) {
      throw new NiflaError(line, 'This loop ran more than a million times and was stopped — it may never end. Check the condition, and make sure something inside the loop changes each time around, so it can finish.');
    }
  }

  run(program) {
    const top = new Scope();
    for (const statement of program) {
      this.execute(statement, top);
    }
  }

  execute(statement, scope) {
    switch (statement.t) {
      case 'declare': {
        if (scope.isDeclaredHere(statement.name)) {
          throw new NiflaError(statement.line, "There is already a variable called '" + statement.name + "' in this block. To change what it holds, write: " + statement.name + ' = ...');
        }
        const value = this.evaluate(statement.value, scope);
        if (statement.kind !== null) {
          this.checkVariableGuard(statement.name, statement.kind, value, statement.line);
          scope.declare(statement.name, value);
          scope.declareAnnotation(statement.name, statement.kind);
        } else {
          scope.declare(statement.name, value);
        }
        return;
      }

      case 'assign': {
        const value = this.evaluate(statement.value, scope);
        const kindWord = scope.annotation(statement.name);
        if (kindWord !== null) {
          this.checkVariableGuard(statement.name, kindWord, value, statement.line);
        }
        if (!scope.assign(statement.name, value)) {
          throw new NiflaError(statement.line, "I can't set '" + statement.name + "', because no variable called '" + statement.name + "' has been made yet. Make one first with: let " + statement.name + ' = ...');
        }
        return;
      }

      case 'assignTarget': {
        // The target is a chain of steps; every step but the
        // last is read, to reach the object or list whose
        // field or item is being set, and the last step
        // names it. Setting a field that isn't there yet
        // adds it.
        this.assignTo(statement.target, statement.value, statement.line, scope);
        return;
      }

      case 'say': {
        const value = this.evaluate(statement.value, scope);
        this.output += spokenOf(value) + '\n';
        return;
      }

      case 'if': {
        const value = this.evaluate(statement.cond, scope);
        if (typeof value !== 'boolean') {
          throw new NiflaError(statement.line, "'if' needs a true or false value to decide with, but here it was given " + describedOf(value) + '. Try a comparison, like: if years > 12 { ... }');
        }
        const block = value ? statement.then : (statement.otherwise || []);
        const child = new Scope(scope);
        for (const inner of block) this.execute(inner, child);
        return;
      }

      case 'while': {
        // The condition is checked before every pass. Each
        // pass runs the body in a fresh block scope: 'let'
        // inside is new each pass, while setting a variable
        // reaches the one outside — that is how counting
        // works.
        while (true) {
          const value = this.evaluate(statement.cond, scope);
          if (typeof value !== 'boolean') {
            throw new NiflaError(statement.line, "'while' needs a true or false value to decide with, but here it was given " + describedOf(value) + '. Try a comparison, like: while years < 40 { ... }');
          }
          if (!value) break;
          this.tickLoop(statement.line);
          const child = new Scope(scope);
          for (const inner of statement.body) this.execute(inner, child);
        }
        return;
      }

      case 'repeat': {
        // The count is worked out once, before the loop
        // starts, and must be a whole number, zero or more.
        const value = this.evaluate(statement.count, scope);
        if (typeof value !== 'number') {
          throw new NiflaError(statement.line, "'repeat' needs a number saying how many times to run, but here it was given " + describedOf(value) + '. Write it like: repeat 3 { ... }');
        }
        const count = value;
        if (count < 0) {
          throw new NiflaError(statement.line, "'repeat' was told to run " + formatNumber(count) + " times, but a count can't be negative — a loop can't run less than zero times. Use zero or more, like: repeat 3 { ... }");
        }
        if (count !== Math.round(count)) {
          throw new NiflaError(statement.line, "'repeat' was told to run " + formatNumber(count) + ' times, but a loop can only run a whole number of times. Use a whole number instead, like ' + formatNumber(Math.floor(count)) + ' or ' + formatNumber(Math.ceil(count)) + '.');
        }
        let done = 0;
        while (done < count) {
          this.tickLoop(statement.line);
          const child = new Scope(scope);
          for (const inner of statement.body) this.execute(inner, child);
          done += 1;
        }
        return;
      }

      case 'for': {
        // The list (or text) is read once, as it stands when
        // the loop begins, and the block runs once for each
        // item in it, with the item under the loop's name.
        const over = this.evaluate(statement.over, scope);
        let items;
        if (over instanceof NList) {
          items = over.items.slice();
        } else if (typeof over === 'string') {
          items = graphemes(over);
        } else if (over instanceof NBytes) {
          items = [...over.data];
        } else {
          throw new NiflaError(statement.line, "'for' needs a list, some text, or a block of bytes to walk through, but here it was given " + describedOf(over) + '. Write it like: for item in items { ... }');
        }
        for (const item of items) {
          this.tickLoop(statement.line);
          const child = new Scope(scope);
          child.declare(statement.name, item);
          for (const inner of statement.body) this.execute(inner, child);
        }
        return;
      }

      case 'define': {
        // Making a function is a line like any other: it
        // runs when the program reaches it, so a function
        // is ready to call from that line on.
        if (BUILTIN_TOOLS[statement.name] !== undefined) {
          throw new NiflaError(statement.line, "There is already a built-in tool called '" + statement.name + "' — every Nifla program has it from the start. A function can't be made with that name; rename the function.");
        }
        if (this.functions.has(statement.name)) {
          throw new NiflaError(statement.line, "There is already a function called '" + statement.name + "'. Each function needs its own name — rename this one, or take out the earlier 'make " + statement.name + "'.");
        }
        this.functions.set(statement.name, {
          params: statement.params,
          paramKinds: statement.paramKinds,
          returnKind: statement.returnKind,
          body: statement.body,
          home: scope,
        });
        return;
      }

      case 'give': {
        if (this.callDepth <= 0) {
          throw new NiflaError(statement.line, "'give' hands a value back from a function to whoever called it, but this line is not inside a function. To show a value here, use 'say' instead.");
        }
        throw new ReturnSignal(this.evaluate(statement.value, scope), statement.line);
      }

      case 'attempt': {
        // Try the first block; if anything in it goes wrong
        // — any plain-words problem, however deep inside it —
        // run the second block instead, with the problem's
        // words held in a variable called 'problem'. A
        // 'give' in either block is not a problem: it hands
        // its value back as always, straight through.
        try {
          const child = new Scope(scope);
          for (const inner of statement.body) this.execute(inner, child);
        } catch (error) {
          if (!(error instanceof NiflaError)) throw error;
          const child = new Scope(scope);
          child.declare('problem', error.message);
          for (const inner of statement.recovery) this.execute(inner, child);
        }
        return;
      }

      case 'doCall': {
        // A call on its own line: run it for what it does.
        // Any value it gives back is simply not used.
        this.callFunction(statement.name, statement.args, statement.line, scope);
        return;
      }

      case 'doExpr': {
        // An expression run for what it does — a floor block
        // standing on its own. Its value goes unused.
        this.evaluate(statement.expr, scope);
        return;
      }
    }
  }

  // Sets the field or item a target chain names. The
  // chain's base is read (which reads every step before the
  // last), the holder the last step names is checked, and
  // only then is the new value worked out.
  assignTo(target, valueExpr, line, scope) {
    if (target.t === 'field') {
      const base = this.evaluate(target.base, scope);
      if (!(base instanceof NObject)) {
        throw new NiflaError(line, "I can't set the field '" + target.name + "' on " + describedOf(base) + ', because only an object has fields. Make an object first, like: let person = { name: "Tyler" } — then person.' + target.name + ' = ... works.');
      }
      base.set(target.name, this.evaluate(valueExpr, scope));
      return;
    }
    if (target.t === 'index') {
      const base = this.evaluate(target.base, scope);
      if (base instanceof NList) {
        const index = this.itemNumber(this.evaluate(target.index, scope), target.line);
        if (base.items.length === 0) {
          throw new NiflaError(target.line, 'This list has no items yet, so there is no item ' + index + ' to set. To add an item at the end, use append — like: append(items, ...).');
        }
        if (index < 0 || index >= base.items.length) {
          throw new NiflaError(target.line, 'This list has ' + base.items.length + ' items, numbered 0 to ' + (base.items.length - 1) + ', so there is no item ' + index + ' to set. To add an item at the end, use append — like: append(items, ...).');
        }
        base.items[index] = this.evaluate(valueExpr, scope);
        return;
      }
      if (base instanceof NBytes) {
        const index = this.itemNumber(this.evaluate(target.index, scope), target.line);
        if (base.data.length === 0) {
          throw new NiflaError(target.line, 'This block of bytes has no bytes yet, so there is no byte ' + index + ' to set. Make a bigger block with makebytes — like: makebytes(8).');
        }
        if (index < 0 || index >= base.data.length) {
          throw new NiflaError(target.line, 'This block of bytes has ' + base.data.length + ' bytes, numbered 0 to ' + (base.data.length - 1) + ', so there is no byte ' + index + ' to set.');
        }
        base.data[index] = this.byteValue(this.evaluate(valueExpr, scope), target.line);
        return;
      }
      if (typeof base === 'string') {
        throw new NiflaError(target.line, "I can't change one character of some text — once text is made, it doesn't change. To change it, build the new text and set the variable to it instead.");
      }
      throw new NiflaError(target.line, 'I can only set an item in a list, like: items[0] = 30 — but this is ' + describedOf(base) + ', which has no items to set.');
    }
    throw new NiflaError(line, 'I can only set a field on an object or an item in a list, like: person.years = 30 or items[0] = 30.');
  }

  // Checks that a value can be stored in a block of bytes:
  // a whole number from 0 to 255.
  byteValue(value, line) {
    if (typeof value !== 'number' || value !== Math.round(value) || value < 0 || value > 255) {
      throw new NiflaError(line, 'A byte is a whole number from 0 to 255, but I was given ' + describedOf(value) + '.');
    }
    return value;
  }

  // Checks that a value can pick an item: a whole number.
  // The range check belongs to the reading or setting, which
  // knows how many items there are.
  itemNumber(value, line) {
    if (typeof value !== 'number') {
      throw new NiflaError(line, "I can't use " + describedOf(value) + ' to pick an item. Items are picked by a whole number — 0 for the first one, 1 for the second, and so on.');
    }
    if (value !== Math.round(value) || Math.abs(value) >= 1e15) {
      throw new NiflaError(line, 'An item number must be a whole number, but I was given ' + formatNumber(value) + '. Use a whole number, like 0, 1, or 2.');
    }
    return Math.trunc(value);
  }

  // Reads one item of a list, one character of some text, or
  // one byte of a block of bytes.
  readIndex(base, indexValue, line) {
    if (base instanceof NList) {
      const index = this.itemNumber(indexValue, line);
      if (base.items.length === 0) {
        throw new NiflaError(line, 'This list has no items yet, so there is no item ' + index + ' to take from it. Items can be added with append — like: append(items, ...).');
      }
      if (index < 0 || index >= base.items.length) {
        throw new NiflaError(line, 'This list has ' + base.items.length + ' items, numbered 0 to ' + (base.items.length - 1) + ', but I was asked for item ' + index + '.');
      }
      return base.items[index];
    }
    if (typeof base === 'string') {
      const index = this.itemNumber(indexValue, line);
      const chars = graphemes(base);
      if (chars.length === 0) {
        throw new NiflaError(line, 'This text has no characters yet, so there is no character ' + index + ' to take from it.');
      }
      if (index < 0 || index >= chars.length) {
        throw new NiflaError(line, 'This text has ' + chars.length + ' characters, numbered 0 to ' + (chars.length - 1) + ', but I was asked for character ' + index + '.');
      }
      return chars[index];
    }
    if (base instanceof NBytes) {
      const index = this.itemNumber(indexValue, line);
      if (base.data.length === 0) {
        throw new NiflaError(line, 'This block of bytes has no bytes yet, so there is no byte ' + index + ' to take from it. Make a bigger block with makebytes — like: makebytes(8).');
      }
      if (index < 0 || index >= base.data.length) {
        throw new NiflaError(line, 'This block of bytes has ' + base.data.length + ' bytes, numbered 0 to ' + (base.data.length - 1) + ', but I was asked for byte ' + index + '.');
      }
      return base.data[index];
    }
    throw new NiflaError(line, "I can't take an item from " + describedOf(base) + '. Only a list or some text has items to take from — like [1, 2, 3], where [0] takes the first item, or "abc", where [0] takes the first character.');
  }

  // Calls a function — a built-in tool or one the program
  // made. Hands back the value it gives, or undefined when
  // it gives nothing back (the caller decides what that
  // means: on its own line it is fine; used as a value it
  // is a problem).
  callFunction(name, argExprs, line, scope) {
    // A built-in tool wins over everything: it cannot be
    // shadowed, and functions cannot be made with its name.
    const tool = BUILTIN_TOOLS[name];
    if (tool !== undefined) {
      const args = argExprs.map(expr => this.evaluate(expr, scope));
      if (args.length !== tool.params.length) {
        throw new NiflaError(line, builtinCountMessage(name, tool, args.length));
      }
      return this.runBuiltin(name, args, line);
    }
    // No such function? Say so plainly, with a suggestion
    // if a similar name exists — a built-in tool or a
    // function made earlier.
    const definition = this.functions.get(name);
    if (definition === undefined) {
      let message = "I don't know a function called '" + name + "' yet. You can make one with: make " + name + '(...) { ... }';
      const guess = this.closestFunctionName(name);
      if (guess !== null) {
        message += " Did you mean '" + guess + "'?";
      }
      throw new NiflaError(line, message);
    }
    const args = argExprs.map(expr => this.evaluate(expr, scope));
    if (args.length !== definition.params.length) {
      throw new NiflaError(line, "The function '" + name + "' takes " + takesText(definition.params) + ', but it was given ' + args.length + '. Make the call match how the function was made: ' + name + '(' + definition.params.join(', ') + ').');
    }
    // The guards at the annotated boundaries of the call —
    // each annotated parameter checks the value handed to
    // it, here at the call.
    for (let index = 0; index < definition.params.length; index++) {
      const kindWord = definition.paramKinds[index];
      if (kindWord !== null && kindWord !== undefined && !kindSatisfies(kindWord, args[index])) {
        throw new NiflaError(line, "The value handed to '" + name + "' for '" + definition.params[index] + "' is " + describedOf(args[index]) + ", but '" + definition.params[index] + "' is marked as " + phraseForKindWord(kindWord) + ' by its annotation. Change what the call hands over, or change the annotation.');
      }
    }
    // The depth guard: a function that calls itself with no
    // way to stop would run forever; stop it kindly instead.
    if (this.callDepth >= this.callDepthLimit) {
      throw new NiflaError(line, "This call is more than five hundred functions deep and was stopped — it may never finish. A function that calls itself needs a way to stop, like an 'if' that gives an answer for the smallest case instead of calling again.");
    }
    this.callDepth += 1;
    // A call runs in a fresh scope: its own 'let's, with the
    // parameters filled in. The body's parent is the scope
    // where the function was made, so the function sees the
    // variables that were around it then.
    const callScope = new Scope(definition.home);
    for (let index = 0; index < definition.params.length; index++) {
      callScope.declare(definition.params[index], args[index]);
      const kindWord = definition.paramKinds[index];
      if (kindWord !== null && kindWord !== undefined) {
        callScope.declareAnnotation(definition.params[index], kindWord);
      }
    }
    try {
      for (const statement of definition.body) {
        this.execute(statement, callScope);
      }
    } catch (error) {
      this.callDepth -= 1;
      if (error instanceof ReturnSignal) {
        const returnKind = definition.returnKind;
        // What the function promised with '-> kind' is kept:
        // a 'give' of the wrong kind is refused as it leaves,
        // at the give's own line.
        if (returnKind !== null && !kindSatisfies(returnKind, error.value)) {
          throw new NiflaError(error.line, "'" + name + "' is marked to give back " + phraseForKindWord(returnKind) + " by its annotation, but this 'give' hands back " + describedOf(error.value) + '. Change the value, or change the annotation.');
        }
        // A function marked '-> nothing' never hands a value
        // back — a 'give nothing' line inside it is an early
        // way out, and the empty value it names is absorbed
        // by the promise.
        if (returnKind === 'nothing') {
          return undefined;
        }
        return error.value;
      }
      throw error;
    }
    this.callDepth -= 1;
    const returnKind = definition.returnKind;
    if (returnKind !== null) {
      // A function marked 'maybe' that finishes without a
      // 'give' hands back the empty value — that is exactly
      // what the mark says may happen.
      if (returnKind.startsWith('maybe ')) {
        return NOTHING;
      }
      if (returnKind !== 'nothing') {
        throw new NiflaError(line, "'" + name + "' is marked to give back " + phraseForKindWord(returnKind) + " by its annotation, but it finished without giving a value back. Add a 'give' line inside '" + name + "', or change the annotation.");
      }
    }
    return undefined;
  }

  // Runs one of the built-in tools. Each tool has already
  // had its arguments checked and counted; here each
  // argument's kind is checked in plain words.
  runBuiltin(name, args, line) {
    switch (name) {
      case 'length': {
        const value = args[0];
        if (typeof value === 'string') return graphemeCount(value);
        if (value instanceof NList) return value.items.length;
        if (value instanceof NObject) return value.fieldNames.length;
        if (value instanceof NBytes) return value.data.length;
        throw new NiflaError(line, "'length' measures some text, a list, an object, or a block of bytes, but it was given " + describedOf(value) + '.');
      }

      case 'makebytes': {
        const count = this.wholeCount(args[0], 'The number of bytes to make', line);
        if (count < 0) {
          throw new NiflaError(line, "'makebytes' was told to make " + count + " bytes, but a count can't be less than 0.");
        }
        if (count > 16777216) {
          throw new NiflaError(line, "'makebytes' was told to make " + count + ' bytes, but one block can hold at most 16777216 bytes.');
        }
        return new NBytes(count);
      }

      case 'join': {
        if (!(args[0] instanceof NList)) {
          throw new NiflaError(line, "'join' joins the items of a list into one piece of text, but it was given " + describedOf(args[0]) + ' to join. Give it a list first, like: join(words, " ").');
        }
        if (typeof args[1] !== 'string') {
          throw new NiflaError(line, "'join' needs some text to join the items with, like \" \" or \", \", but it was given " + describedOf(args[1]) + '.');
        }
        return args[0].items.map(item => spokenOf(item)).join(args[1]);
      }

      case 'split': {
        if (typeof args[0] !== 'string') {
          throw new NiflaError(line, "'split' splits some text into a list of pieces, but it was given " + describedOf(args[0]) + ' to split.');
        }
        if (typeof args[1] !== 'string') {
          throw new NiflaError(line, "'split' needs some text to split by, like \",\", but it was given " + describedOf(args[1]) + '.');
        }
        if (args[1] === '') {
          throw new NiflaError(line, "'split' can't split by an empty piece of text — there would be nothing to split on. Give it the text to split by, like: split(\"a,b\", \",\").");
        }
        return new NList(args[0].split(args[1]));
      }

      case 'part': {
        if (typeof args[0] !== 'string') {
          throw new NiflaError(line, "'part' takes a part of some text, but it was given " + describedOf(args[0]) + '.');
        }
        if (typeof args[1] !== 'number') {
          throw new NiflaError(line, "'part' needs a number saying which character to start at — 0 is the first — but it was given " + describedOf(args[1]) + '.');
        }
        if (typeof args[2] !== 'number') {
          throw new NiflaError(line, "'part' needs a number saying how many characters to take, but it was given " + describedOf(args[2]) + '.');
        }
        const start = this.wholeCount(args[1], 'The character to start at', line);
        const count = this.wholeCount(args[2], 'The number of characters to take', line);
        const chars = graphemes(args[0]);
        if (start < 0) {
          throw new NiflaError(line, "'part' was told to start at character " + start + ", but the first character is number 0 — a start can't be less than 0.");
        }
        if (count < 0) {
          throw new NiflaError(line, "'part' was told to take " + count + " characters, but a count can't be less than 0.");
        }
        if (start > chars.length) {
          if (chars.length === 0) {
            throw new NiflaError(line, "'part' was told to start at character " + start + ', but the text has no characters yet.');
          }
          throw new NiflaError(line, "'part' was told to start at character " + start + ', but the text has only ' + chars.length + ' characters, numbered 0 to ' + (chars.length - 1) + '.');
        }
        if (start + count > chars.length) {
          throw new NiflaError(line, "'part' was told to take " + count + ' characters starting at character ' + start + ', but the text has only ' + chars.length + ' characters, numbered 0 to ' + (chars.length - 1) + ' — that runs past the end.');
        }
        return chars.slice(start, start + count).join('');
      }

      case 'find': {
        if (typeof args[0] !== 'string') {
          throw new NiflaError(line, "'find' looks for a piece of text inside some text, but it was given " + describedOf(args[0]) + ' to look in.');
        }
        if (typeof args[1] !== 'string') {
          throw new NiflaError(line, "'find' looks for a piece of text inside some text, but it was given " + describedOf(args[1]) + ' to look for.');
        }
        const chars = graphemes(args[0]);
        const wanted = graphemes(args[1]);
        if (wanted.length === 0) return 0;
        if (wanted.length > chars.length) return -1;
        for (let start = 0; start + wanted.length <= chars.length; start++) {
          let matches = true;
          for (let offset = 0; offset < wanted.length; offset++) {
            if (chars[start + offset] !== wanted[offset]) { matches = false; break; }
          }
          if (matches) return start;
        }
        return -1;
      }

      case 'append': {
        if (!(args[0] instanceof NList)) {
          throw new NiflaError(line, "'append' adds a value to the end of a list, but it was given " + describedOf(args[0]) + ' to add to.');
        }
        args[0].items.push(args[1]);
        return args[0];
      }

      case 'readfile': {
        if (typeof args[0] !== 'string') {
          throw new NiflaError(line, "'readfile' needs the name of a file, as text, but it was given " + describedOf(args[0]) + '.');
        }
        const entry = this.store.get(args[0]);
        if (entry === undefined) {
          throw new NiflaError(line, "I couldn't read the file '" + args[0] + "'. Check the name and the folder, and try again.");
        }
        if (typeof entry === 'string') return entry;
        try {
          return utf8DecodeStrict(entry);
        } catch (error) {
          throw new NiflaError(line, "I couldn't read the file '" + args[0] + "'. Check the name and the folder, and try again.");
        }
      }

      case 'readbytes': {
        if (typeof args[0] !== 'string') {
          throw new NiflaError(line, "'readbytes' needs the name of a file, as text, but it was given " + describedOf(args[0]) + '.');
        }
        const entry = this.store.get(args[0]);
        if (entry === undefined) {
          throw new NiflaError(line, "I couldn't read the file '" + args[0] + "'. Check the name and the folder, and try again.");
        }
        const bytes = typeof entry === 'string' ? utf8Encode(entry) : new Uint8Array(entry);
        if (bytes.length > 16777216) {
          throw new NiflaError(line, "'readbytes' read the file '" + args[0] + "', but it holds " + bytes.length + ' bytes, and one block can hold at most 16777216 bytes.');
        }
        const block = new NBytes(bytes.length);
        block.data.set(bytes);
        return block;
      }

      case 'asnumber': {
        // Stone 26: a number read out of text. Text that
        // isn't a number written plainly is a problem,
        // and 'attempt' can catch it.
        if (typeof args[0] !== 'string') {
          throw new NiflaError(line, "'asnumber' needs some text to read a number from, but it was given " + describedOf(args[0]) + '.');
        }
        const value = readNumberText(args[0]);
        if (value === null) {
          throw new NiflaError(line, "'" + args[0] + "' is not a number 'asnumber' can read. A number is written with digits, a '-' first when it is below zero, and at most one '.' with digits after it — like 620 or -3.5.");
        }
        return value;
      }

      case 'bitand':
      case 'bitor':
      case 'bitxor': {
        // Stone 27: the bit tools — a bit stands in
        // the answer when it stands in both numbers
        // (bitand), in either one (bitor), or in one
        // but not the other (bitxor). The work the
        // self-made feather checker does by hand in
        // its 'xorbyte', given single words at last.
        const first = bitToolNumber(args[0], name, line);
        const second = bitToolNumber(args[1], name, line);
        if (name === 'bitand') return combineBits(first, second, (x, y) => x && y);
        if (name === 'bitor') return combineBits(first, second, (x, y) => x || y);
        return combineBits(first, second, (x, y) => x !== y);
      }

      case 'astext': {
        // Stone 28: the text of a block of bytes — the
        // road back from bytes to text. The bytes are
        // read as UTF-8; a run of bytes that is not a
        // letter stands in the text as the replacement
        // mark, the way every reader shows it — never
        // dropped, never guessed at.
        if (!(args[0] instanceof NBytes)) {
          throw new NiflaError(line, "'astext' needs a block of bytes to read as text, but it was given " + describedOf(args[0]) + '.');
        }
        return utf8Decode(args[0].data);
      }

      case 'writefile': {
        if (typeof args[0] !== 'string') {
          throw new NiflaError(line, "'writefile' needs the name of a file, as text, but it was given " + describedOf(args[0]) + '.');
        }
        if (typeof args[1] !== 'string') {
          throw new NiflaError(line, "'writefile' writes some text to a file, but it was given " + describedOf(args[1]) + ' to write.');
        }
        this.store.set(args[0], args[1]);
        return graphemeCount(args[1]);
      }

      case 'arguments': {
        return new NList(this.programArguments.slice());
      }

      case 'sayerr': {
        // Like say, but to the error output. Gives back the
        // number of characters written, counting the new
        // line — the tool's reason to exist as a call, not
        // just a line.
        const text = spokenOf(args[0]);
        this.errorOutput += text + '\n';
        return graphemeCount(text) + 1;
      }

      case 'exitwith': {
        if (typeof args[0] !== 'number') {
          throw new NiflaError(line, "'exitwith' ends the program with a number as its parting word to the system, but it was given " + describedOf(args[0]) + '.');
        }
        const code = args[0];
        if (code !== Math.round(code) || code < 0 || code > 255) {
          throw new NiflaError(line, "'exitwith' needs a whole number from 0 to 255, but it was given " + formatNumber(code) + '.');
        }
        throw new ExitSignal(Math.trunc(code));
      }

      case 'removeat': {
        if (!(args[0] instanceof NList)) {
          throw new NiflaError(line, "'removeat' takes an item out of a list, but it was given " + describedOf(args[0]) + ' to take from.');
        }
        const index = this.itemNumber(args[1], line);
        const list = args[0];
        if (list.items.length === 0) {
          throw new NiflaError(line, 'This list has no items yet, so there is no item ' + index + ' to remove.');
        }
        if (index < 0 || index >= list.items.length) {
          throw new NiflaError(line, 'This list has ' + list.items.length + ' items, numbered 0 to ' + (list.items.length - 1) + ', but I was asked to remove item ' + index + '.');
        }
        return list.items.splice(index, 1)[0];
      }

      case 'insertat': {
        if (!(args[0] instanceof NList)) {
          throw new NiflaError(line, "'insertat' puts an item into a list, but it was given " + describedOf(args[0]) + ' to put into.');
        }
        const index = this.itemNumber(args[1], line);
        const list = args[0];
        if (index < 0 || index > list.items.length) {
          throw new NiflaError(line, 'This list has ' + list.items.length + ' items, so a new item can be put in at numbers 0 to ' + list.items.length + ', but I was asked for number ' + index + '.');
        }
        list.items.splice(index, 0, args[2]);
        return list;
      }

      case 'sorted': {
        if (!(args[0] instanceof NList)) {
          throw new NiflaError(line, "'sorted' sorts a list, but it was given " + describedOf(args[0]) + ' to sort.');
        }
        return new NList(this.sortedItems(args[0].items, line));
      }

      case 'fieldnames': {
        if (!(args[0] instanceof NObject)) {
          throw new NiflaError(line, "'fieldnames' lists the field names of an object, as a list of text, but it was given " + describedOf(args[0]) + '.');
        }
        return new NList(args[0].fieldNames.slice());
      }

      case 'removefield': {
        if (!(args[0] instanceof NObject)) {
          throw new NiflaError(line, "'removefield' takes a field out of an object, but it was given " + describedOf(args[0]) + ' to take from.');
        }
        if (typeof args[1] !== 'string') {
          throw new NiflaError(line, "'removefield' needs the name of a field, as text, but it was given " + describedOf(args[1]) + '.');
        }
        const removed = args[0].remove(args[1]);
        if (removed === undefined) {
          throw this.missingFieldError(args[0], args[1], line);
        }
        return removed;
      }

      default: {
        throw new NiflaError(line, "I don't know a tool called '" + name + "'.");
      }
    }
  }

  // The refusal for a missing field, with the object's
  // fields listed and a suggestion when a near name exists.
  missingFieldError(object, name, line) {
    if (object.fieldNames.length === 0) {
      return new NiflaError(line, "This object has no fields yet, so it has no field called '" + name + "'. You can add one by setting it, like: person." + name + ' = ...');
    }
    let message = "This object has no field called '" + name + "'. Its fields are: " + object.fieldNames.join(', ') + '.';
    const guess = this.closestFieldName(object, name);
    if (guess !== null) {
      message += " Did you mean '" + guess + "'?";
    }
    return new NiflaError(line, message);
  }

  // A near field name on the object, if any — within two
  // edits, the closest one.
  closestFieldName(object, name) {
    let best = null;
    let bestDistance = Infinity;
    for (const candidate of object.fieldNames) {
      if (candidate === name) continue;
      const distance = editDistance(name, candidate);
      if (distance <= 2 && distance < bestDistance) {
        best = candidate;
        bestDistance = distance;
      }
    }
    return best;
  }

  // A near variable name visible from here, if any.
  closestName(name, scope) {
    let best = null;
    let bestDistance = Infinity;
    for (const candidate of scope.allNames()) {
      if (candidate === name) continue;
      const distance = editDistance(name, candidate);
      if (distance <= 2 && distance < bestDistance) {
        best = candidate;
        bestDistance = distance;
      }
    }
    return best;
  }

  // A near function or tool name, if any.
  closestFunctionName(name) {
    const candidates = [...this.functions.keys()].concat(Object.keys(BUILTIN_TOOLS));
    let best = null;
    let bestDistance = Infinity;
    for (const candidate of candidates) {
      if (candidate === name) continue;
      const distance = editDistance(name, candidate);
      if (distance <= 2 && distance < bestDistance) {
        best = candidate;
        bestDistance = distance;
      }
    }
    return best;
  }

  // Sorts a list's items — all numbers (smallest first) or
  // all text (in order) — or refuses in plain words. Every
  // item must be the same kind as the first.
  sortedItems(items, line) {
    if (items.length === 0) return [];
    const first = items[0];
    if (typeof first === 'number') {
      for (let index = 0; index < items.length; index++) {
        if (typeof items[index] !== 'number') {
          throw new NiflaError(line, "'sorted' needs every item in the list to be the same kind — numbers with numbers, text with text — but item " + index + ' is ' + describedOf(items[index]) + ', while the first item is ' + describedOf(first) + '.');
        }
      }
      return items.slice().sort((a, b) => (a < b ? -1 : a > b ? 1 : 0));
    }
    if (typeof first === 'string') {
      for (let index = 0; index < items.length; index++) {
        if (typeof items[index] !== 'string') {
          throw new NiflaError(line, "'sorted' needs every item in the list to be the same kind — numbers with numbers, text with text — but item " + index + ' is ' + describedOf(items[index]) + ', while the first item is ' + describedOf(first) + '.');
        }
      }
      return items.slice().sort(compareText);
    }
    throw new NiflaError(line, "'sorted' can sort a list of numbers or a list of text, but this list starts with " + describedOf(first) + '.');
  }

  // A count that must be a whole number.
  wholeCount(value, what, line) {
    if (typeof value !== 'number') {
      throw new NiflaError(line, what + ' must be a number, but I was given ' + describedOf(value) + '.');
    }
    if (value !== Math.round(value) || Math.abs(value) >= 1e15) {
      throw new NiflaError(line, what + ' must be a whole number, but I was given ' + formatNumber(value) + '.');
    }
    return Math.trunc(value);
  }

  // The guard on a promised kind: a variable made with a
  // kind mark refuses a value of the wrong kind whenever it
  // is set.
  checkVariableGuard(name, kindWord, value, line) {
    if (!kindSatisfies(kindWord, value)) {
      throw new NiflaError(line, "'" + name + "' is marked as " + phraseForKindWord(kindWord) + ' by its annotation, but this value is ' + describedOf(value) + '. Change the value, or change the annotation.');
    }
  }

  // A floor block, run on the floor desk (see the desk's
  // own note below): the arguments are handed over exactly
  // as the compiled door hands them — whole numbers and at
  // most one block of bytes, refused in the same plain words
  // the runtime speaks when a hand is wrong — and what comes
  // back is the number the block left as its main answer,
  // or the list when it wrote extra answers.
  runFloorBlock(expression, scope) {
    const args = expression.args.map(arg => this.evaluate(arg, scope));
    const numbers = [];
    let bytesValue = null;
    for (const arg of args) {
      if (typeof arg === 'number') {
        if (!Number.isInteger(arg) || Math.abs(arg) >= 1e15) {
          throw new NiflaError(expression.line, 'A floor block can be handed only whole numbers, but it was handed ' + describedOf(arg) + '.');
        }
        numbers.push(BigInt(arg));
      } else if (arg instanceof NBytes) {
        if (bytesValue !== null) {
          throw new NiflaError(expression.line, 'A floor block can be handed only one block of bytes, but it was handed two.');
        }
        bytesValue = arg;
      } else {
        throw new NiflaError(expression.line, 'A floor block can be handed numbers and one block of bytes, but it was given ' + describedOf(arg) + '.');
      }
    }
    const program = assembledFloor(expression);
    const desk = new FloorDesk(numbers, bytesValue ? bytesValue.data : null, expression.line, (text, toError) => {
      if (toError) {
        this.errorOutput += text;
      } else {
        this.output += text;
      }
    });
    const result = desk.run(program);
    if (result.extras.length === 0) return result.headline;
    return new NList([result.headline].concat(result.extras));
  }

  evaluate(expression, scope) {
    switch (expression.t) {
      case 'num': return expression.v;
      case 'text': return expression.v;
      case 'bool': return expression.v;
      case 'nothing': return NOTHING;

      case 'floor': {
        return this.runFloorBlock(expression, scope);
      }

      case 'var': {
        const value = scope.lookup(expression.name);
        if (value === undefined) {
          let message = "I don't know a variable called '" + expression.name + "' yet. You can make one with: let " + expression.name + ' = ...';
          const guess = this.closestName(expression.name, scope);
          if (guess !== null) {
            message += " Did you mean '" + guess + "'?";
          }
          throw new NiflaError(expression.line, message);
        }
        return value;
      }

      case 'call': {
        const value = this.callFunction(expression.name, expression.args, expression.line, scope);
        if (value === undefined) {
          throw new NiflaError(expression.line, "The function '" + expression.name + "' finished without giving a value back, so there is nothing to use here. Add a 'give' line inside '" + expression.name + "', or call it on its own line instead.");
        }
        return value;
      }

      case 'object': {
        const object = new NObject();
        for (const field of expression.fields) {
          object.set(field.name, this.evaluate(field.value, scope));
        }
        return object;
      }

      case 'list': {
        return new NList(expression.items.map(item => this.evaluate(item, scope)));
      }

      case 'field': {
        const base = this.evaluate(expression.base, scope);
        if (!(base instanceof NObject)) {
          throw new NiflaError(expression.line, "I can't read the field '" + expression.name + "' of " + describedOf(base) + ', because only an object has fields. Make an object first, like: let person = { name: "Tyler" } — then person.name works.');
        }
        if (!base.values.has(expression.name)) {
          throw this.missingFieldError(base, expression.name, expression.line);
        }
        return base.values.get(expression.name);
      }

      case 'index': {
        const base = this.evaluate(expression.base, scope);
        const index = this.evaluate(expression.index, scope);
        return this.readIndex(base, index, expression.line);
      }

      case 'neg': {
        const value = this.evaluate(expression.expr, scope);
        if (typeof value !== 'number') {
          throw new NiflaError(expression.line, 'I can only put a minus sign in front of a number, but here it was in front of ' + describedOf(value) + '.');
        }
        return -value;
      }

      case 'bin': {
        const left = this.evaluate(expression.left, scope);
        const right = this.evaluate(expression.right, scope);
        return this.apply(expression.op, left, right, expression.line);
      }
    }
    throw new NiflaError(expression.line, 'I could not run this part of the program.');
  }

  apply(op, left, right, line) {
    const leftNothing = left === NOTHING;
    const rightNothing = right === NOTHING;
    switch (op) {
      case '+': {
        // Text joins with anything, the way JavaScript joins
        // strings.
        if (typeof left === 'string' || typeof right === 'string') {
          return spokenOf(left) + spokenOf(right);
        }
        if (typeof left === 'number' && typeof right === 'number') {
          return left + right;
        }
        if (leftNothing || rightNothing) {
          throw new NiflaError(line, "I can't add " + describedOf(left) + ' and ' + describedOf(right) + ". '+' adds two numbers, or joins text together." + NOTHING_NOTE);
        }
        throw new NiflaError(line, "I can't add " + describedOf(left) + ' and ' + describedOf(right) + ". '+' adds two numbers, or joins text together.");
      }
      case '-': case '*': case '/': {
        if (typeof left === 'number' && typeof right === 'number') {
          if (op === '-') return left - right;
          if (op === '*') return left * right;
          if (right === 0) {
            throw new NiflaError(line, "I can't divide by zero. Dividing needs a second number that isn't zero.");
          }
          return left / right;
        }
        const verb = op === '-' ? 'subtract' : (op === '*' ? 'multiply' : 'divide');
        if (leftNothing || rightNothing) {
          throw new NiflaError(line, "I can't " + verb + ' ' + describedOf(left) + ' and ' + describedOf(right) + ". '" + op + "' works on two numbers. (Only '+' joins text.)" + NOTHING_NOTE);
        }
        throw new NiflaError(line, "I can't " + verb + ' ' + describedOf(left) + ' and ' + describedOf(right) + ". '" + op + "' works on two numbers. (Only '+' joins text.)");
      }
      case '==': return valuesEqual(left, right);
      case '!=': return !valuesEqual(left, right);
      case '<': case '<=': case '>': case '>=': {
        if (typeof left === 'number' && typeof right === 'number') {
          if (op === '<') return left < right;
          if (op === '<=') return left <= right;
          if (op === '>') return left > right;
          return left >= right;
        }
        if (leftNothing || rightNothing) {
          throw new NiflaError(line, "I can't compare " + describedOf(left) + ' and ' + describedOf(right) + " with '" + op + "'. '" + op + "' compares two numbers. (Text and true/false values can be checked with == and !=.)" + NOTHING_NOTE);
        }
        throw new NiflaError(line, "I can't compare " + describedOf(left) + ' and ' + describedOf(right) + " with '" + op + "'. '" + op + "' compares two numbers. (Text and true/false values can be checked with == and !=.)");
      }
    }
    throw new NiflaError(line, "I don't know the sign '" + op + "'.");
  }
}

// Equality between two values: numbers, text, and true/false
// compare by what they hold; objects, lists, and blocks of
// bytes compare by being the very same one; 'nothing' equals
// 'nothing'; different kinds are never equal.
function valuesEqual(left, right) {
  if (left === NOTHING || right === NOTHING) {
    return left === NOTHING && right === NOTHING;
  }
  if (typeof left === 'number' && typeof right === 'number') return left === right;
  if (typeof left === 'string' && typeof right === 'string') return left === right;
  if (typeof left === 'boolean' && typeof right === 'boolean') return left === right;
  if (left instanceof NObject && right instanceof NObject) return left === right;
  if (left instanceof NList && right instanceof NList) return left === right;
  if (left instanceof NBytes && right instanceof NBytes) return left === right;
  return false;
}

// ----------------------------------------------------------------
// The entry point's floor scan: the first floor block
// anywhere in the program — however deeply nested — refuses
// the run with its line. (Checked after the checker, the
// same order as the Swift entry point.)
// ----------------------------------------------------------------

function collectFloorExprsInStmts(statements, out) {
  for (const statement of statements) {
    collectFloorExprsInStmt(statement, out);
  }
}

function collectFloorExprsInStmt(statement, out) {
  switch (statement.t) {
    case 'declare':
    case 'assign':
    case 'say':
    case 'give':
      collectFloorExprsInExpr(statement.value, out);
      return;
    case 'assignTarget':
      collectFloorExprsInExpr(statement.target, out);
      collectFloorExprsInExpr(statement.value, out);
      return;
    case 'if':
      collectFloorExprsInExpr(statement.cond, out);
      collectFloorExprsInStmts(statement.then, out);
      if (statement.otherwise) collectFloorExprsInStmts(statement.otherwise, out);
      return;
    case 'while':
      collectFloorExprsInExpr(statement.cond, out);
      collectFloorExprsInStmts(statement.body, out);
      return;
    case 'repeat':
      collectFloorExprsInExpr(statement.count, out);
      collectFloorExprsInStmts(statement.body, out);
      return;
    case 'for':
      collectFloorExprsInExpr(statement.over, out);
      collectFloorExprsInStmts(statement.body, out);
      return;
    case 'define':
      collectFloorExprsInStmts(statement.body, out);
      return;
    case 'attempt':
      collectFloorExprsInStmts(statement.body, out);
      collectFloorExprsInStmts(statement.recovery, out);
      return;
    case 'doCall':
      for (const arg of statement.args) {
        collectFloorExprsInExpr(arg, out);
      }
      return;
    case 'doExpr':
      collectFloorExprsInExpr(statement.expr, out);
      return;
    default:
      return;
  }
}

function collectFloorExprsInExpr(expression, out) {
  switch (expression.t) {
    case 'floor':
      out.push(expression);
      return;
    case 'call':
      for (const arg of expression.args) {
        collectFloorExprsInExpr(arg, out);
      }
      return;
    case 'object':
      for (const field of expression.fields) {
        collectFloorExprsInExpr(field.value, out);
      }
      return;
    case 'list':
      for (const item of expression.items) {
        collectFloorExprsInExpr(item, out);
      }
      return;
    case 'field':
      collectFloorExprsInExpr(expression.base, out);
      return;
    case 'neg':
      collectFloorExprsInExpr(expression.inner, out);
      return;
    case 'index':
      collectFloorExprsInExpr(expression.base, out);
      collectFloorExprsInExpr(expression.index, out);
      return;
    case 'bin':
      collectFloorExprsInExpr(expression.left, out);
      collectFloorExprsInExpr(expression.right, out);
      return;
    default:
      return;
  }
}


// ----------------------------------------------------------------
// The floor desk: floor code, run on a simulated desk.
//
// The compiled door hands a floor block real registers and
// real memory (the Primer's Part 4 tells the contract). This
// door has no real processor to hand it to, so it keeps a
// desk: a small, honest simulation of that same contract.
// The desk holds the sixteen registers as 64-bit values, the
// flags the jumps read, and four pieces of memory — the
// numbers handed in, the one block of bytes (the very same
// bytes the program holds, so what the block writes there
// stays written), the answers area, and a stack. The block's
// assembly text is read by a small assembler and carried out
// instruction by instruction.
//
// The desk covers the instructions Nifla's own books and
// tests use: moving (mov, lea, push, pop), arithmetic (add,
// sub, imul, mul, div, idiv, inc, dec, neg, not), logic and
// comparing (xor, and, or, cmp, test), shifts (shl, shr,
// sar), the jumps (jmp and the condition family), nop and
// its kin, and the write call (syscall number 1, to the
// program's own output and error channels). A block using
// anything else is refused before it runs — before anything
// in the program runs — in plain words naming the
// instruction, the same honesty the compiled door's checker
// keeps when it refuses what it can prove wrong before a
// run. The desk's other limits are named the same way when
// a block reaches them: memory outside the desk, a division
// by zero, and a runaway block (ten million instructions is
// the desk's patience, so a web page stays alive). Registers
// the contract does not name start at zero and the stack
// starts empty: the desk is the same every run, so a learner
// sees the same thing twice.
// ----------------------------------------------------------------

// A coverage refusal: the block uses something the desk does
// not cover. Carries the whole plain-words message; the
// caller wraps it with the block's line.
class DeskRefusal extends Error {}

function deskUncovered(detail) {
  return new DeskRefusal('This floor block uses ' + detail + ", which the browser's floor desk does not cover. The desk covers the instructions Nifla's own books and tests use — moving, adding, subtracting, multiplying, dividing, comparing, jumping, and the write call. To run this block, build the program with niflac and run the program it makes.");
}

function deskUnreadable(detail) {
  return new DeskRefusal("The browser's floor desk cannot read this floor block: " + detail + '. The desk reads assembly the way the compiled door\'s assembler does, in the instructions Nifla\'s own books and tests use. To run this block, build the program with niflac and run the program it makes.');
}

const DESK_STEP_LIMIT = 10000000;
const DESK_NUMBERS_AT = 0x10000000n;
const DESK_BYTES_AT = 0x20000000n;
const DESK_RESULTS_AT = 0x30000000n;
const DESK_STACK_AT = 0x40000000n;
const DESK_STACK_SIZE = 65536;

// Register parts: every name a block can use, mapped to its
// register (0–15, in the order rax rbx rcx rdx rsi rdi rbp
// rsp r8…r15), its width in bytes, and whether it is the
// high byte of the low word (ah, bh, ch, dh).
const REGISTER_PARTS = (() => {
  const parts = {};
  const base = [
    ['rax', 'eax', 'ax', 'al', 'ah'], ['rbx', 'ebx', 'bx', 'bl', 'bh'],
    ['rcx', 'ecx', 'cx', 'cl', 'ch'], ['rdx', 'edx', 'dx', 'dl', 'dh'],
    ['rsi', 'esi', 'si', 'sil', null], ['rdi', 'edi', 'di', 'dil', null],
    ['rbp', 'ebp', 'bp', 'bpl', null], ['rsp', 'esp', 'sp', 'spl', null]
  ];
  base.forEach((names, i) => {
    parts[names[0]] = { reg: i, size: 8, high: false };
    parts[names[1]] = { reg: i, size: 4, high: false };
    parts[names[2]] = { reg: i, size: 2, high: false };
    parts[names[3]] = { reg: i, size: 1, high: false };
    if (names[4]) parts[names[4]] = { reg: i, size: 1, high: true };
  });
  for (let i = 8; i < 16; i++) {
    parts['r' + i] = { reg: i, size: 8, high: false };
    parts['r' + i + 'd'] = { reg: i, size: 4, high: false };
    parts['r' + i + 'w'] = { reg: i, size: 2, high: false };
    parts['r' + i + 'b'] = { reg: i, size: 1, high: false };
  }
  return parts;
})();

function deskMask(size) {
  return (1n << BigInt(size * 8)) - 1n;
}

function deskSigned(value, size) {
  const bits = BigInt(size * 8);
  const sign = 1n << (bits - 1n);
  const masked = value & deskMask(size);
  return (masked & sign) !== 0n ? masked - (1n << bits) : masked;
}

// Split an operand list on the commas that stand outside
// memory brackets.
function splitFloorOperands(text) {
  const out = [];
  let depth = 0;
  let current = '';
  for (const ch of text) {
    if (ch === '[') depth++;
    if (ch === ']') depth--;
    if (ch === ',' && depth === 0) {
      out.push(current);
      current = '';
    } else {
      current += ch;
    }
  }
  if (current.trim()) out.push(current);
  return out;
}

function parseFloorOperand(rawText) {
  let text = rawText.trim();
  let memSize = null;
  const qualifier = text.match(/^(byte|word|dword|qword)\s+ptr\s+/i);
  if (qualifier) {
    memSize = { byte: 1, word: 2, dword: 4, qword: 8 }[qualifier[1].toLowerCase()];
    text = text.slice(qualifier[0].length).trim();
  }
  const part = REGISTER_PARTS[text.toLowerCase()];
  if (part) return { kind: 'reg', reg: part.reg, size: part.size, high: part.high };
  if (text.startsWith('[') && text.endsWith(']')) {
    const inner = text.slice(1, -1).replace(/\s+/g, '');
    const terms = inner.match(/[+-]?[^+-]+/g) || [];
    let base = null;
    let index = null;
    let scale = 1;
    let disp = 0n;
    for (const rawTerm of terms) {
      let term = rawTerm;
      let sign = 1n;
      if (term.startsWith('+')) {
        term = term.slice(1);
      } else if (term.startsWith('-')) {
        sign = -1n;
        term = term.slice(1);
      }
      const star = term.split('*');
      if (star.length === 2) {
        let regName = null;
        let scaleText = null;
        const first = REGISTER_PARTS[star[0].toLowerCase()];
        const second = REGISTER_PARTS[star[1].toLowerCase()];
        if (first && first.size === 8) { regName = star[0]; scaleText = star[1]; }
        else if (second && second.size === 8) { regName = star[1]; scaleText = star[0]; }
        else throw deskUnreadable("an address the desk cannot read: '[" + inner + "]'");
        const s = Number(scaleText);
        if (![1, 2, 4, 8].includes(s) || sign < 0n || index !== null) {
          throw deskUnreadable("an address the desk cannot read: '[" + inner + "]'");
        }
        index = REGISTER_PARTS[regName.toLowerCase()].reg;
        scale = s;
      } else if (REGISTER_PARTS[term.toLowerCase()] && REGISTER_PARTS[term.toLowerCase()].size === 8) {
        const reg = REGISTER_PARTS[term.toLowerCase()].reg;
        if (base === null) base = reg;
        else if (index === null) { index = reg; scale = 1; }
        else throw deskUnreadable("an address the desk cannot read: '[" + inner + "]'");
      } else if (/^(\d+|0x[0-9a-fA-F]+)$/.test(term)) {
        disp += sign * BigInt(term);
      } else {
        throw deskUnreadable("an address the desk cannot read: '[" + inner + "]'");
      }
    }
    return { kind: 'mem', size: memSize, base, index, scale, disp };
  }
  if (/^[+-]?(\d+|0x[0-9a-fA-F]+)$/.test(text)) {
    let digits = text;
    let negative = false;
    if (digits.startsWith('+')) digits = digits.slice(1);
    else if (digits.startsWith('-')) { negative = true; digits = digits.slice(1); }
    const value = BigInt(digits);
    return { kind: 'imm', value: negative ? -value : value };
  }
  if (/^[A-Za-z_.$][\w.$]*$/.test(text) || /^\d+[bf]$/.test(text)) {
    return { kind: 'label', name: text.toLowerCase() };
  }
  throw deskUnreadable("words the desk cannot read: '" + rawText.trim() + "'");
}

const DESK_JUMPS = ['jmp', 'je', 'jz', 'jne', 'jnz', 'ja', 'jae', 'jb', 'jbe',
  'jg', 'jge', 'jl', 'jle', 'js', 'jns', 'jo', 'jno'];

// Read a block's assembly text into instructions the desk
// can carry out, resolving its labels. Anything the desk
// does not cover is refused here, in plain words.
function assembleFloorBlock(asmText) {
  const instructions = [];
  const namedLabels = new Map();
  const numericLabels = [];
  for (const rawLine of asmText.split('\n')) {
    let line = rawLine;
    const hashAt = line.indexOf('#');
    if (hashAt >= 0) line = line.slice(0, hashAt);
    const slashesAt = line.indexOf('//');
    if (slashesAt >= 0) line = line.slice(0, slashesAt);
    for (let statement of line.split(';')) {
      statement = statement.trim();
      if (!statement) continue;
      let labelMatch;
      while ((labelMatch = statement.match(/^([A-Za-z_.$][\w.$]*|\d+):\s*/))) {
        const name = labelMatch[1].toLowerCase();
        if (/^\d+$/.test(name)) {
          numericLabels.push({ num: name, at: instructions.length });
        } else {
          if (namedLabels.has(name)) {
            throw deskUnreadable("the label '" + name + "' set down twice");
          }
          namedLabels.set(name, instructions.length);
        }
        statement = statement.slice(labelMatch[0].length).trim();
        if (!statement) break;
      }
      if (!statement) continue;
      const spaceAt = statement.search(/\s/);
      const mnemonic = (spaceAt < 0 ? statement : statement.slice(0, spaceAt)).toLowerCase();
      const operandText = spaceAt < 0 ? '' : statement.slice(spaceAt + 1).trim();
      const operands = operandText ? splitFloorOperands(operandText).map(parseFloorOperand) : [];
      instructions.push({ op: mnemonic, operands });
    }
  }
  for (const instruction of instructions) {
    if (DESK_JUMPS.includes(instruction.op)) {
      if (instruction.operands.length !== 1 || instruction.operands[0].kind !== 'label') {
        throw deskUnreadable("a '" + instruction.op + "' whose target the desk cannot read");
      }
      const name = instruction.operands[0].name;
      const numeric = name.match(/^(\d+)([bf])$/);
      if (numeric) {
        const at = instructions.indexOf(instruction);
        const same = numericLabels.filter(entry => entry.num === numeric[1]);
        if (numeric[2] === 'b') {
          const before = same.filter(entry => entry.at <= at);
          if (before.length === 0) {
            throw deskUnreadable("a jump back to label '" + numeric[1] + "' that was never set down before it");
          }
          instruction.target = before[before.length - 1].at;
        } else {
          const after = same.filter(entry => entry.at > at);
          if (after.length === 0) {
            throw deskUnreadable("a jump forward to label '" + numeric[1] + "' that is never set down after it");
          }
          instruction.target = after[0].at;
        }
      } else {
        if (!namedLabels.has(name)) {
          throw deskUnreadable("a jump to the label '" + name + "', which this block never sets down");
        }
        instruction.target = namedLabels.get(name);
      }
    }
  }
  for (const instruction of instructions) validateFloorInstruction(instruction);
  return instructions;
}

// The working width of an instruction, from its operands —
// and the shape rules the desk holds every instruction to.
function floorOperandSize(instruction, operands, needsMemoryWidth) {
  let size = null;
  for (const operand of operands) {
    if (operand.kind === 'reg') {
      if (size !== null && size !== operand.size) {
        throw deskUncovered("a '" + instruction.op + "' whose two sides are different widths");
      }
      size = operand.size;
    } else if (operand.kind === 'mem' && operand.size !== null) {
      if (size !== null && size !== operand.size) {
        throw deskUncovered("a '" + instruction.op + "' whose two sides are different widths");
      }
      size = operand.size;
    }
  }
  if (size === null && needsMemoryWidth) {
    throw deskUncovered("a '" + instruction.op + "' that works on memory without saying how wide — byte ptr, word ptr, dword ptr, or qword ptr");
  }
  return size;
}

function validateFloorInstruction(instruction) {
  const ops = instruction.operands;
  const op = instruction.op;
  const twoOperandAlu = ['mov', 'add', 'sub', 'xor', 'and', 'or', 'cmp', 'test'];
  if (twoOperandAlu.includes(op)) {
    if (ops.length !== 2) throw deskUncovered("a '" + op + "' with " + ops.length + ' side' + (ops.length === 1 ? '' : 's'));
    const [dst, src] = ops;
    if (dst.kind !== 'reg' && dst.kind !== 'mem') throw deskUncovered("a '" + op + "' with nowhere to put its answer");
    if (src.kind !== 'reg' && src.kind !== 'mem' && src.kind !== 'imm') throw deskUncovered("a '" + op + "' whose second side the desk cannot read");
    if (dst.kind === 'mem' && src.kind === 'mem') throw deskUncovered("a '" + op + "' that goes from memory to memory");
    if (op === 'mov' && dst.kind === 'mem' && src.kind === 'imm' && dst.size === null) {
      throw deskUncovered("a 'mov' that puts a number into memory without saying how wide — byte ptr, word ptr, dword ptr, or qword ptr");
    }
    instruction.size = floorOperandSize(instruction, ops, false) || 8;
    return;
  }
  if (op === 'lea') {
    if (ops.length !== 2 || ops[0].kind !== 'reg' || ops[1].kind !== 'mem') {
      throw deskUncovered("a 'lea' that is not a register taking an address");
    }
    instruction.size = ops[0].size;
    return;
  }
  if (op === 'imul') {
    if (ops.length === 1) {
      if (ops[0].kind !== 'reg' && ops[0].kind !== 'mem') throw deskUncovered("an 'imul' with nothing to multiply");
      instruction.size = floorOperandSize(instruction, ops, true);
      return;
    }
    if (ops.length === 2 || ops.length === 3) {
      if (ops[0].kind !== 'reg') throw deskUncovered("an 'imul' with nowhere to put its answer");
      if (ops[1].kind !== 'reg' && ops[1].kind !== 'mem' && ops[1].kind !== 'imm') throw deskUncovered("an 'imul' whose second side the desk cannot read");
      if (ops.length === 3 && ops[2].kind !== 'imm') throw deskUncovered("an 'imul' whose third side is not a number");
      if (ops.length === 2) floorOperandSize(instruction, ops, false);
      instruction.size = ops[0].size;
      return;
    }
    throw deskUncovered("an 'imul' with " + ops.length + ' sides');
  }
  if (op === 'mul' || op === 'div' || op === 'idiv') {
    if (ops.length !== 1 || (ops[0].kind !== 'reg' && ops[0].kind !== 'mem')) {
      throw deskUncovered("a '" + op + "' that is not dividing or multiplying by one thing");
    }
    instruction.size = floorOperandSize(instruction, ops, true);
    return;
  }
  if (op === 'inc' || op === 'dec' || op === 'neg' || op === 'not') {
    if (ops.length !== 1 || (ops[0].kind !== 'reg' && ops[0].kind !== 'mem')) {
      throw deskUncovered("a '" + op + "' with nothing to work on");
    }
    instruction.size = floorOperandSize(instruction, ops, true);
    return;
  }
  if (op === 'push') {
    if (ops.length !== 1 || ops[0].kind === 'label') throw deskUncovered("a 'push' of something the desk cannot push");
    if (ops[0].kind === 'reg' && ops[0].size !== 8) throw deskUncovered("a 'push' of a part of a register");
    instruction.size = 8;
    return;
  }
  if (op === 'pop') {
    if (ops.length !== 1 || (ops[0].kind !== 'reg' && ops[0].kind !== 'mem')) throw deskUncovered("a 'pop' with nowhere to land");
    if (ops[0].kind === 'reg' && ops[0].size !== 8) throw deskUncovered("a 'pop' into a part of a register");
    instruction.size = 8;
    return;
  }
  if (op === 'shl' || op === 'shr' || op === 'sar') {
    if (ops.length !== 2 || (ops[0].kind !== 'reg' && ops[0].kind !== 'mem')) {
      throw deskUncovered("a '" + op + "' that is not shifting one thing by a count");
    }
    const count = ops[1];
    const isCl = count.kind === 'reg' && count.reg === 2 && count.size === 1 && !count.high;
    if (count.kind !== 'imm' && !isCl) throw deskUncovered("a '" + op + "' whose count is not a number or cl");
    instruction.size = floorOperandSize(instruction, [ops[0]], true);
    return;
  }
  if (DESK_JUMPS.includes(op)) return;
  if (op === 'nop' || op === 'cld' || op === 'std' || op === 'syscall') {
    if (ops.length !== 0) throw deskUncovered("a '" + op + "' with words after it");
    return;
  }
  throw deskUncovered("the instruction '" + op + "'");
}

// The desk itself: registers, flags, and the four pieces of
// memory, carrying out one assembled block.
class FloorDesk {
  constructor(numbers, bytesData, line, writeOut) {
    this.line = line;
    this.writeOut = writeOut;
    this.regs = new Array(16).fill(0n);
    this.flags = { zf: false, sf: false, cf: false, of: false };
    const numbersBytes = new Uint8Array(numbers.length * 8);
    numbers.forEach((value, i) => {
      let x = value & 0xffffffffffffffffn;
      for (let b = 0; b < 8; b++) {
        numbersBytes[i * 8 + b] = Number(x & 0xffn);
        x >>= 8n;
      }
    });
    this.regions = [
      { at: DESK_NUMBERS_AT, data: numbersBytes },
      { at: DESK_RESULTS_AT, data: new Uint8Array(64) },
      { at: DESK_STACK_AT, data: new Uint8Array(DESK_STACK_SIZE) }
    ];
    if (bytesData) this.regions.push({ at: DESK_BYTES_AT, data: bytesData });
    // The contract, as the Primer tells it: r10 and r11 hand
    // over the numbers, rbx and r12 the one block of bytes,
    // r13 the answers area, r14 the count of extra answers
    // (none yet). With no bytes handed in, rbx is 0, as the
    // compiled door's wrapper leaves it.
    this.regs[10] = DESK_NUMBERS_AT;
    this.regs[11] = BigInt(numbers.length);
    this.regs[1] = bytesData ? DESK_BYTES_AT : 0n;
    this.regs[12] = BigInt(bytesData ? bytesData.length : 0);
    this.regs[13] = DESK_RESULTS_AT;
    this.regs[14] = 0n;
    this.regs[7] = DESK_STACK_AT + BigInt(DESK_STACK_SIZE);
  }

  locate(address, size) {
    for (const region of this.regions) {
      if (address >= region.at && address + BigInt(size) <= region.at + BigInt(region.data.length)) {
        return { data: region.data, offset: Number(address - region.at) };
      }
    }
    return null;
  }

  outsideFault(address) {
    return new NiflaError(this.line, 'This floor block reached for memory outside its desk — the address ' + address + ' is not part of the numbers handed in, the block of bytes, the answers area, or its stack. On real metal that reach would land wherever it pointed; the desk stops it here so the mistake can be seen.');
  }

  readMem(address, size) {
    const place = this.locate(address, size);
    if (!place) throw this.outsideFault(address);
    let value = 0n;
    for (let i = size - 1; i >= 0; i--) {
      value = (value << 8n) | BigInt(place.data[place.offset + i]);
    }
    return value;
  }

  writeMem(address, size, value) {
    const place = this.locate(address, size);
    if (!place) throw this.outsideFault(address);
    let x = value & deskMask(size);
    for (let i = 0; i < size; i++) {
      place.data[place.offset + i] = Number(x & 0xffn);
      x >>= 8n;
    }
  }

  getReg(part) {
    const value = this.regs[part.reg];
    if (part.size === 8) return value;
    if (part.size === 4) return value & 0xffffffffn;
    if (part.size === 2) return value & 0xffffn;
    if (part.high) return (value >> 8n) & 0xffn;
    return value & 0xffn;
  }

  setReg(part, value) {
    const masked = value & deskMask(part.size);
    if (part.size === 8 || part.size === 4) {
      // A four-byte write clears the top half, as the
      // processor does; an eight-byte write is the whole.
      this.regs[part.reg] = masked;
    } else if (part.size === 2) {
      this.regs[part.reg] = (this.regs[part.reg] & ~0xffffn) | masked;
    } else if (part.high) {
      this.regs[part.reg] = (this.regs[part.reg] & ~0xff00n) | (masked << 8n);
    } else {
      this.regs[part.reg] = (this.regs[part.reg] & ~0xffn) | masked;
    }
  }

  addressOf(operand) {
    let address = operand.disp;
    if (operand.base !== null) address += this.regs[operand.base];
    if (operand.index !== null) address += this.regs[operand.index] * BigInt(operand.scale);
    return address;
  }

  readOperand(operand, size) {
    if (operand.kind === 'reg') return this.getReg(operand);
    if (operand.kind === 'imm') return operand.value & deskMask(size);
    return this.readMem(this.addressOf(operand), size);
  }

  writeOperand(operand, size, value) {
    if (operand.kind === 'reg') {
      this.setReg(operand, value);
      return;
    }
    this.writeMem(this.addressOf(operand), size, value);
  }

  setZN(result, size) {
    const masked = result & deskMask(size);
    this.flags.zf = masked === 0n;
    this.flags.sf = ((masked >> BigInt(size * 8 - 1)) & 1n) === 1n;
  }

  addFlags(a, b, size) {
    const result = a + b;
    const masked = result & deskMask(size);
    this.flags.cf = result > deskMask(size);
    const signA = ((a >> BigInt(size * 8 - 1)) & 1n) === 1n;
    const signB = ((b >> BigInt(size * 8 - 1)) & 1n) === 1n;
    const signR = ((masked >> BigInt(size * 8 - 1)) & 1n) === 1n;
    this.flags.of = signA === signB && signR !== signA;
    this.setZN(result, size);
    return masked;
  }

  subFlags(a, b, size) {
    const result = a - b;
    const masked = result & deskMask(size);
    this.flags.cf = a < b;
    const signA = ((a >> BigInt(size * 8 - 1)) & 1n) === 1n;
    const signB = ((b >> BigInt(size * 8 - 1)) & 1n) === 1n;
    const signR = ((masked >> BigInt(size * 8 - 1)) & 1n) === 1n;
    this.flags.of = signA !== signB && signR !== signA;
    this.setZN(result, size);
    return masked;
  }

  run(instructions) {
    let pc = 0;
    let steps = 0;
    while (pc < instructions.length) {
      steps++;
      if (steps > DESK_STEP_LIMIT) {
        throw new NiflaError(this.line, 'This floor block ran past ten million instructions without stopping, so the desk stopped it. On real metal it would keep going; in a web page it has to stop so the page stays alive. The block may be in a loop that never ends.');
      }
      pc = this.execute(instructions[pc], pc);
    }
    const headline = Number(deskSigned(this.regs[0], 8));
    let extraCount = this.regs[14];
    if (extraCount > 8n) extraCount = 8n;
    if (extraCount < 0n) extraCount = 0n;
    const extras = [];
    for (let i = 0; i < Number(extraCount); i++) {
      extras.push(Number(deskSigned(this.readMem(DESK_RESULTS_AT + BigInt(i * 8), 8), 8)));
    }
    return { headline, extras };
  }

  jumpTaken(op) {
    const f = this.flags;
    switch (op) {
      case 'jmp': return true;
      case 'je': case 'jz': return f.zf;
      case 'jne': case 'jnz': return !f.zf;
      case 'ja': return !f.cf && !f.zf;
      case 'jae': return !f.cf;
      case 'jb': return f.cf;
      case 'jbe': return f.cf || f.zf;
      case 'jg': return !f.zf && f.sf === f.of;
      case 'jge': return f.sf === f.of;
      case 'jl': return f.sf !== f.of;
      case 'jle': return f.zf || f.sf !== f.of;
      case 'js': return f.sf;
      case 'jns': return !f.sf;
      case 'jo': return f.of;
      case 'jno': return !f.of;
      default: return false;
    }
  }

  execute(instruction, pc) {
    const op = instruction.op;
    const ops = instruction.operands;
    const size = instruction.size || 8;
    const next = pc + 1;
    if (DESK_JUMPS.includes(op)) {
      return this.jumpTaken(op) ? instruction.target : next;
    }
    switch (op) {
      case 'nop': case 'cld': case 'std':
        return next;
      case 'mov': {
        this.writeOperand(ops[0], size, this.readOperand(ops[1], size));
        return next;
      }
      case 'lea': {
        this.setReg(ops[0], this.addressOf(ops[1]));
        return next;
      }
      case 'add': case 'sub': case 'xor': case 'and': case 'or': case 'cmp': case 'test': {
        const a = this.readOperand(ops[0], size);
        const b = this.readOperand(ops[1], size);
        let result;
        if (op === 'add') result = this.addFlags(a, b, size);
        else if (op === 'sub' || op === 'cmp') result = this.subFlags(a, b, size);
        else {
          if (op === 'xor') result = a ^ b;
          else if (op === 'and' || op === 'test') result = a & b;
          else result = a | b;
          this.flags.cf = false;
          this.flags.of = false;
          this.setZN(result, size);
        }
        if (op !== 'cmp' && op !== 'test') this.writeOperand(ops[0], size, result);
        return next;
      }
      case 'inc': case 'dec': {
        const a = this.readOperand(ops[0], size);
        const savedCF = this.flags.cf;
        const result = op === 'inc' ? this.addFlags(a, 1n, size) : this.subFlags(a, 1n, size);
        this.flags.cf = savedCF;
        if (op === 'inc') this.flags.of = result === (1n << BigInt(size * 8 - 1));
        else this.flags.of = a === (1n << BigInt(size * 8 - 1));
        this.writeOperand(ops[0], size, result);
        return next;
      }
      case 'neg': {
        const a = this.readOperand(ops[0], size);
        const result = (-a) & deskMask(size);
        this.flags.cf = a !== 0n;
        this.flags.of = a === (1n << BigInt(size * 8 - 1));
        this.setZN(result, size);
        this.writeOperand(ops[0], size, result);
        return next;
      }
      case 'not': {
        const a = this.readOperand(ops[0], size);
        this.writeOperand(ops[0], size, ~a & deskMask(size));
        return next;
      }
      case 'imul': {
        const acc = { reg: 0, size, high: false };
        const accHigh = { reg: 3, size, high: false };
        if (ops.length === 1) {
          const b = deskSigned(this.readOperand(ops[0], size), size);
          const a = deskSigned(this.getReg(acc), size);
          const product = a * b;
          const low = product & deskMask(size);
          const high = (product >> BigInt(size * 8)) & deskMask(size);
          this.setReg(acc, low);
          this.setReg(accHigh, high);
          const fits = deskSigned(low, size) === product;
          this.flags.cf = !fits;
          this.flags.of = !fits;
          return next;
        }
        const product = ops.length === 2
          ? deskSigned(this.readOperand(ops[0], size), size) * deskSigned(this.readOperand(ops[1], size), size)
          : deskSigned(this.readOperand(ops[1], size), size) * ops[2].value;
        const truncated = product & deskMask(size);
        const fits = deskSigned(truncated, size) === product;
        this.flags.cf = !fits;
        this.flags.of = !fits;
        this.writeOperand(ops[0], size, truncated);
        return next;
      }
      case 'mul': {
        const acc = { reg: 0, size, high: false };
        const accHigh = { reg: 3, size, high: false };
        const b = this.readOperand(ops[0], size);
        const a = this.getReg(acc);
        const product = a * b;
        const low = product & deskMask(size);
        const high = (product >> BigInt(size * 8)) & deskMask(size);
        this.setReg(acc, low);
        this.setReg(accHigh, high);
        this.flags.cf = high !== 0n;
        this.flags.of = high !== 0n;
        return next;
      }
      case 'div': case 'idiv': {
        const acc = { reg: 0, size, high: false };
        const accHigh = { reg: 3, size, high: false };
        const bits = BigInt(size * 8);
        const rawDivisor = this.readOperand(ops[0], size);
        const dividendBits = (this.getReg(accHigh) << bits) | this.getReg(acc);
        if (op === 'div') {
          if (rawDivisor === 0n) {
            throw new NiflaError(this.line, 'This floor block divided by zero. On real metal the processor faults at that instruction and the program stops.');
          }
          const quotient = dividendBits / rawDivisor;
          const remainder = dividendBits % rawDivisor;
          if (quotient > deskMask(size)) {
            throw new NiflaError(this.line, "This floor block's division made an answer too big to hold. On real metal the processor faults at that instruction and the program stops.");
          }
          this.setReg(acc, quotient);
          this.setReg(accHigh, remainder);
          return next;
        }
        const divisor = deskSigned(rawDivisor, size);
        if (divisor === 0n) {
          throw new NiflaError(this.line, 'This floor block divided by zero. On real metal the processor faults at that instruction and the program stops.');
        }
        const dividend = deskSigned(dividendBits, size * 2);
        const quotient = dividend / divisor;
        const remainder = dividend % divisor;
        const maxSigned = (1n << (bits - 1n)) - 1n;
        const minSigned = -(1n << (bits - 1n));
        if (quotient > maxSigned || quotient < minSigned) {
          throw new NiflaError(this.line, "This floor block's division made an answer too big to hold. On real metal the processor faults at that instruction and the program stops.");
        }
        this.setReg(acc, quotient & deskMask(size));
        this.setReg(accHigh, remainder & deskMask(size));
        return next;
      }
      case 'push': {
        const value = ops[0].kind === 'imm' ? ops[0].value & deskMask(8) : this.readOperand(ops[0], 8);
        const rsp = this.regs[7] - 8n;
        this.writeMem(rsp, 8, value);
        this.regs[7] = rsp;
        return next;
      }
      case 'pop': {
        const value = this.readMem(this.regs[7], 8);
        this.regs[7] += 8n;
        this.writeOperand(ops[0], 8, value);
        return next;
      }
      case 'shl': case 'shr': case 'sar': {
        const a = this.readOperand(ops[0], size);
        let count;
        if (ops[1].kind === 'imm') count = Number(ops[1].value & 63n);
        else count = Number(this.getReg({ reg: 2, size: 1, high: false }) & 63n);
        count = count & (size === 8 ? 63 : 31);
        if (count === 0) return next;
        const bits = size * 8;
        let result;
        if (op === 'shl') {
          this.flags.cf = ((a >> BigInt(bits - count)) & 1n) === 1n;
          result = (a << BigInt(count)) & deskMask(size);
          if (count === 1) this.flags.of = this.flags.cf !== (((result >> BigInt(bits - 1)) & 1n) === 1n);
        } else if (op === 'shr') {
          this.flags.cf = ((a >> BigInt(count - 1)) & 1n) === 1n;
          result = a >> BigInt(count);
          if (count === 1) this.flags.of = ((a >> BigInt(bits - 1)) & 1n) === 1n;
        } else {
          this.flags.cf = ((a >> BigInt(count - 1)) & 1n) === 1n;
          result = deskSigned(a, size) >> BigInt(count);
          result = result & deskMask(size);
          if (count === 1) this.flags.of = false;
        }
        this.setZN(result, size);
        this.writeOperand(ops[0], size, result);
        return next;
      }
      case 'syscall': {
        const call = this.regs[0];
        if (call !== 1n) {
          throw new NiflaError(this.line, 'This floor block asked the processor for call number ' + call + ". The desk covers only the write call (number 1) — the one a block uses to say something. A real machine's system answers the other calls; this desk is not one.");
        }
        const fd = this.regs[5];
        const buffer = this.regs[4];
        const count = this.regs[3];
        if (fd === 1n || fd === 2n) {
          if (count > 16777216n) throw this.outsideFault(buffer);
          const bytes = new Uint8Array(Number(count));
          for (let i = 0; i < bytes.length; i++) {
            bytes[i] = Number(this.readMem(buffer + BigInt(i), 1));
          }
          const text = new TextDecoder('utf-8').decode(bytes);
          this.writeOut(text, fd === 2n);
          this.regs[0] = count;
        } else {
          // A write to a channel the program does not hold:
          // the real call answers with its bad-channel
          // number, -9, and nothing is written.
          this.regs[0] = (-9n) & deskMask(8);
        }
        // The write call spends rcx and r11, as the
        // processor does.
        this.regs[2] = 0n;
        this.regs[11] = 0n;
        return next;
      }
      default:
        // validateFloorInstruction refused everything the
        // desk does not cover before the block ran, so this
        // is unreachable; the refusal stands guard anyway.
        throw deskUncovered("the instruction '" + op + "'");
    }
  }
}

// Assembled blocks, remembered per program node so the
// entry point's coverage proof and the run itself read the
// same instructions.
const floorAssemblyCache = new WeakMap();

function assembledFloor(expression) {
  let program = floorAssemblyCache.get(expression);
  if (!program) {
    try {
      program = assembleFloorBlock(expression.asm);
    } catch (error) {
      if (error instanceof DeskRefusal) {
        throw new NiflaError(expression.line, error.message);
      }
      throw error;
    }
    floorAssemblyCache.set(expression, program);
  }
  return program;
}

// ----------------------------------------------------------------
// The public door: run a Nifla program.
//
//   run(source, { args, files }) ->
//     { output, errorOutput, exitCode, error, files }
//
// See the note at the top of this file for the full
// description. The run mirrors the Swift entry point exactly:
// read the program, check it before anything runs, prove
// every floor block is one the desk covers, then run it.
// ----------------------------------------------------------------

function runNifla(source, options) {
  const opts = options || {};
  const args = (opts.args || []).map(value => String(value));
  const store = new Map();
  if (opts.files) {
    for (const path of Object.keys(opts.files)) {
      const contents = opts.files[path];
      store.set(path, contents instanceof Uint8Array ? new Uint8Array(contents) : String(contents));
    }
  }
  const filesOut = () => {
    const out = {};
    for (const [path, contents] of store) {
      out[path] = contents instanceof Uint8Array ? new Uint8Array(contents) : contents;
    }
    return out;
  };
  let interpreter = null;
  try {
    const tokens = new Lexer(source).tokenize();
    const program = new Parser(tokens).parseProgram();
    new Checker(program).check(program);
    const floorExprs = [];
    collectFloorExprsInStmts(program, floorExprs);
    for (const floorExpr of floorExprs) {
      assembledFloor(floorExpr);
    }
    interpreter = new Interpreter(store, args);
    interpreter.run(program);
    return {
      output: interpreter.output,
      errorOutput: interpreter.errorOutput,
      exitCode: 0,
      error: null,
      files: filesOut(),
    };
  } catch (error) {
    if (error instanceof ExitSignal) {
      return {
        output: interpreter ? interpreter.output : '',
        errorOutput: interpreter ? interpreter.errorOutput : '',
        exitCode: error.code,
        error: null,
        files: filesOut(),
      };
    }
    if (error instanceof NiflaError) {
      const priorErrors = interpreter ? interpreter.errorOutput : '';
      return {
        output: interpreter ? interpreter.output : '',
        errorOutput: priorErrors + error.spoken + '\n',
        exitCode: 1,
        error: error.spoken,
        files: filesOut(),
      };
    }
    throw error;
  }
}

const Nifla = { run: runNifla };
if (typeof module !== 'undefined' && module.exports) {
  module.exports = Nifla;
}
global.Nifla = Nifla;

})(globalThis);
