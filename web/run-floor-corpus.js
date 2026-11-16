// The floor desk's proof runner: the floor corpus through
// the JavaScript interpreter's simulated desk (web/nifla.js),
// compared against the expectations the Swift suites already
// record — nothing here invents its own expectations for the
// corpus parts:
//
//   - floor-examples/ (run-floor.sh): each program's stdout
//     compared byte for byte with its .expected file.
//   - checker-examples/ floor programs: the checker's
//     refusals, compared byte for byte with their .error
//     files, with nothing run.
//   - PRIMER.md and TUTORIAL.md ```nifla-floor examples,
//     run with the arguments Ada and Byron and compared with
//     the ```expected block that follows each, the same way
//     the book proofs run them.
//
// Then the desk's own honesty tests, written for this proof:
// a block using an instruction the desk does not cover is
// refused before anything in the program runs; a block
// reaching outside its desk, dividing by zero, asking for a
// call the desk does not answer, or running away is stopped
// in plain words naming the limit; and the runtime's
// handed-value refusals speak the runtime's own words.

'use strict';

const fs = require('fs');
const path = require('path');
const Nifla = require('./nifla.js');

const ROOT = path.join(__dirname, '..');

let totalFailures = 0;

function reportFailure(label, detail) {
  totalFailures += 1;
  console.log('FAIL ' + label);
  if (detail) console.log(detail);
}

function expectRun(label, source, wantOutput) {
  const result = Nifla.run(source, { args: [] });
  if (result.exitCode === 0 && result.errorOutput === '' && result.output === wantOutput) {
    console.log('PASS ' + label);
    return true;
  }
  reportFailure(label + ' (expected:)',
    wantOutput + '--- actual (exit ' + result.exitCode + ') ---\n' + result.output + result.errorOutput);
  return false;
}

function expectRefusal(label, source, fragments, wantSilentOutput) {
  const result = Nifla.run(source, { args: [] });
  const missing = fragments.filter(f => !result.errorOutput.includes(f));
  if (result.exitCode !== 0 && missing.length === 0 &&
      (!wantSilentOutput || result.output === '')) {
    console.log('PASS ' + label);
    return true;
  }
  reportFailure(label + ' (expected a refusal naming: ' + fragments.join(' | ') + ')',
    '--- actual (exit ' + result.exitCode + ') ---\n' + result.output + result.errorOutput);
  return false;
}

// ----------------------------------------------------------------
// The floor suite: floor-examples/*.nifla
// ----------------------------------------------------------------

function runFloorExamples() {
  const dir = path.join(ROOT, 'floor-examples');
  const programs = fs.readdirSync(dir).filter(f => f.endsWith('.nifla')).sort();
  let pass = 0;
  for (const file of programs) {
    const name = file.replace(/\.nifla$/, '');
    const source = fs.readFileSync(path.join(dir, file), 'utf8');
    const wantOutput = fs.readFileSync(path.join(dir, name + '.expected'), 'utf8');
    if (expectRun('floor-examples/' + name, source, wantOutput)) pass += 1;
  }
  console.log('---');
  console.log('Floor suite: ' + pass + ' passed, ' + (programs.length - pass) + ' failed, of ' + programs.length);
}

// ----------------------------------------------------------------
// The checker's floor refusals: checker-examples/*floor*.nifla
// ----------------------------------------------------------------

function runCheckerFloor() {
  const dir = path.join(ROOT, 'checker-examples');
  const programs = fs.readdirSync(dir).filter(f => f.endsWith('.nifla') && f.includes('floor')).sort();
  let pass = 0;
  for (const file of programs) {
    const name = file.replace(/\.nifla$/, '');
    const source = fs.readFileSync(path.join(dir, file), 'utf8');
    const wantError = fs.readFileSync(path.join(dir, name + '.error'), 'utf8');
    const result = Nifla.run(source, { args: [] });
    if (result.exitCode !== 0 && result.output === '' && result.errorOutput === wantError) {
      console.log('PASS checker-examples/' + name);
      pass += 1;
    } else {
      reportFailure('checker-examples/' + name + ' (expected a clean failure with this error:)',
        wantError + '--- actual (exit ' + result.exitCode + ') ---\n' + result.output + result.errorOutput);
    }
  }
  console.log('---');
  console.log('Checker floor refusals: ' + pass + ' passed, ' + (programs.length - pass) + ' failed, of ' + programs.length);
}

// ----------------------------------------------------------------
// The books' floor examples: PRIMER.md / TUTORIAL.md
// ----------------------------------------------------------------

function extractBlocks(text) {
  const blocks = [];
  let pos = 0;
  while (true) {
    const start = text.indexOf('```', pos);
    if (start < 0) break;
    const endOfLine = text.indexOf('\n', start);
    const info = text.slice(start + 3, endOfLine).trim();
    const close = text.indexOf('```', endOfLine);
    if (close < 0) return null;
    blocks.push({ info, body: text.slice(endOfLine + 1, close) });
    pos = close + 3;
  }
  return blocks;
}

function runBookFloor(bookFile) {
  const text = fs.readFileSync(path.join(ROOT, bookFile), 'utf8');
  const blocks = extractBlocks(text);
  if (blocks === null) {
    reportFailure(bookFile + ': an unclosed fenced block');
    return 0;
  }
  let seen = 0;
  let pass = 0;
  let i = 0;
  while (i < blocks.length) {
    const { info, body } = blocks[i];
    if (info !== 'nifla-floor') {
      i += 1;
      continue;
    }
    seen += 1;
    const label = bookFile + ' floor example ' + seen;
    if (i + 1 >= blocks.length || blocks[i + 1].info !== 'expected') {
      reportFailure(label + ' is not followed by an ```expected block');
      i += 1;
      continue;
    }
    let want = blocks[i + 1].body;
    if (want.endsWith('\n')) want = want.slice(0, -1);
    const wantOut = want ? want + '\n' : '';
    const result = Nifla.run(body, { args: ['Ada', 'Byron'], files: {} });
    if (result.exitCode === 0 && result.output === wantOut) {
      console.log('PASS ' + label);
      pass += 1;
    } else {
      reportFailure(label + ': output differs',
        '  expected: ' + JSON.stringify(wantOut) + '\n  got:      ' +
        JSON.stringify(result.output + result.errorOutput) + ' (exit ' + result.exitCode + ')');
    }
    i += 2;
  }
  console.log(bookFile + ' floor examples: ' + pass + ' passed, ' + (seen - pass) + ' failed, of ' + seen);
  return seen;
}

// ----------------------------------------------------------------
// The desk's honesty tests
// ----------------------------------------------------------------

function runHonestyTests() {
  let pass = 0;
  let total = 0;
  const test = (ok) => { total += 1; if (ok) pass += 1; };

  // An instruction the desk does not cover: refused before
  // anything in the program runs — even the say before it.
  test(expectRefusal('honesty: uncovered instruction refused before anything runs', `
say "before"
let x = floor(21) {
    movzx rax, byte ptr [r10]
}
say x
`, ["'movzx'", 'does not cover'], true));

  // A reach outside the desk's memory.
  test(expectRefusal('honesty: memory outside the desk', `
let x = floor(5) {
    mov rax, [r10 + 8000]
}
say x
`, ['outside its desk'], true));

  // A division by zero.
  test(expectRefusal('honesty: division by zero', `
let x = floor(5) {
    mov rcx, 0
    div rcx
}
say x
`, ['divided by zero'], true));

  // A call the desk does not answer.
  test(expectRefusal('honesty: a call other than the write call', `
let x = floor() {
    mov rax, 39
    syscall
}
say x
`, ['call number 39', 'write call'], true));

  // A block that never stops.
  test(expectRefusal('honesty: a runaway block is stopped', `
let x = floor() {
1:
    jmp 1b
}
say x
`, ['ten million instructions'], true));

  // The runtime's own handed-value words, reached at run
  // time through a function's unmarked parameter.
  test(expectRefusal('honesty: handed text at run time', `
make tryit(v) {
    let x = floor(v) {
        mov rax, 1
    }
    say x
}
tryit("hello")
`, ['A floor block can be handed numbers and one block of bytes, but it was given the text "hello".'], true));

  test(expectRefusal('honesty: handed a part number at run time', `
make tryit(v) {
    let x = floor(v) {
        mov rax, 1
    }
    say x
}
tryit(2.5)
`, ['A floor block can be handed only whole numbers, but it was handed the number 2.5.'], true));

  test(expectRefusal('honesty: handed two blocks of bytes at run time', `
make trytwo(a, b) {
    let x = floor(a, b) {
        mov rax, 1
    }
    say x
}
trytwo(makebytes(2), makebytes(3))
`, ['A floor block can be handed only one block of bytes, but it was handed two.'], true));

  // The desk's arithmetic beyond the corpus: extra answers
  // and a negative headline.
  test(expectRun('honesty: extra answers and a negative headline', `
let pair = floor(20, 4) {
    mov rax, [r10]
    sub rax, [r10 + 8]
    mov [r13], rax
    mov rax, [r10]
    add rax, [r10 + 8]
    mov r14, 1
}
say pair[0]
say pair[1]
let diff = floor(4, 20) {
    mov rax, [r10]
    sub rax, [r10 + 8]
}
say diff
`, '24\n16\n-16\n'));

  console.log('---');
  console.log('Desk honesty tests: ' + pass + ' passed, ' + (total - pass) + ' failed, of ' + total);
}

runFloorExamples();
runCheckerFloor();
runBookFloor('PRIMER.md');
runBookFloor('TUTORIAL.md');
runHonestyTests();

console.log('---');
if (totalFailures > 0) {
  console.log('WEB FLOOR CORPUS: ' + totalFailures + ' failure(s)');
  process.exit(1);
}
console.log('WEB FLOOR CORPUS PASS');
