// The Browser Stone's proof runner: runs the existing hosted
// conformance corpus through the JavaScript interpreter
// (web/nifla.js) under Node, and compares every program's
// behavior against the expectations the Swift suites already
// record. It mirrors the Swift proofs:
//
//   - examples/ (run_tests.sh): each program's stdout, stderr,
//     and success/failure compared byte for byte with its
//     .expected or .error file.
//   - PRIMER.md (run-primer.sh) and TUTORIAL.md
//     (run-tutorial.sh): every hosted example extracted the
//     same way, run with the arguments Ada and Byron, and its
//     stdout and exit code compared with the ```expected
//     block that follows it. The Primer's examples share one
//     paper-store (the Swift proof shares one folder); the
//     Tutorial's each get a fresh one (the Swift proof gives
//     each run its own fresh folder).
//
// One documented platform difference, printed as a note,
// not silently skipped:
//
//   - ```nifla-bare and ```nifla-bare-guest examples are
//     compile-only on every door (the Swift proof compiles
//     them and runs them on bare metal elsewhere); they are
//     counted and noted, not run.
//
// ```nifla-floor examples run here on the floor desk (see
// nifla.js) and are compared like the hosted examples. The
// desk's own proof — the floor suites and the blocks it
// honestly refuses — is run-web-floor.sh.

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

// ----------------------------------------------------------------
// The interpreted suite: examples/*.nifla
// ----------------------------------------------------------------

function runExamples() {
  const dir = path.join(ROOT, 'examples');
  const programs = fs.readdirSync(dir).filter(f => f.endsWith('.nifla')).sort();
  let pass = 0;
  for (const file of programs) {
    const name = file.replace(/\.nifla$/, '');
    const source = fs.readFileSync(path.join(dir, file), 'utf8');
    const errorPath = path.join(dir, name + '.error');
    const expectedPath = path.join(dir, name + '.expected');
    const result = Nifla.run(source, { args: [] });
    if (fs.existsSync(errorPath)) {
      const wantError = fs.readFileSync(errorPath, 'utf8');
      if (result.exitCode !== 0 && result.output === '' && result.errorOutput === wantError) {
        console.log('PASS ' + name);
        pass += 1;
      } else {
        reportFailure(name + ' (expected a clean failure with this error:)',
          fs.readFileSync(errorPath, 'utf8') +
          '--- actual (exit ' + result.exitCode + ') ---\n' +
          result.output + result.errorOutput);
      }
    } else {
      const wantOutput = fs.readFileSync(expectedPath, 'utf8');
      if (result.exitCode === 0 && result.errorOutput === '' && result.output === wantOutput) {
        console.log('PASS ' + name);
        pass += 1;
      } else {
        reportFailure(name + ' (expected:)',
          wantOutput +
          '--- actual (exit ' + result.exitCode + ') ---\n' +
          result.output + result.errorOutput);
      }
    }
  }
  console.log('---');
  console.log('Interpreted suite: ' + pass + ' passed, ' + (programs.length - pass) + ' failed, of ' + programs.length);
  return programs.length;
}

// ----------------------------------------------------------------
// A book's examples: PRIMER.md / TUTORIAL.md
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

function runBook(bookFile, sharedStore) {
  const text = fs.readFileSync(path.join(ROOT, bookFile), 'utf8');
  const blocks = extractBlocks(text);
  if (blocks === null) {
    reportFailure(bookFile + ': an unclosed fenced block');
    return;
  }
  let ran = 0;
  let failed = 0;
  let seen = 0;
  let compileOnly = 0;
  let failuresBefore = totalFailures;
  let store = {};
  let i = 0;
  while (i < blocks.length) {
    const { info, body } = blocks[i];
    if (info === 'expected') {
      reportFailure(bookFile + ': an ```expected block with no example before it');
      i += 1;
      continue;
    }
    const isExample = info === 'nifla' || info.startsWith('nifla ') ||
      info === 'nifla-floor' || info === 'nifla-bare' || info === 'nifla-bare-guest';
    if (!isExample) {
      i += 1;
      continue;
    }
    seen += 1;
    const label = bookFile + ' example ' + seen + ' (' + info + ')';
    if (info === 'nifla-bare' || info === 'nifla-bare-guest') {
      console.log('NOTE ' + label + ': bare-metal example — compile-only on every door; not run here.');
      compileOnly += 1;
      i += 1;
      continue;
    }
    if (i + 1 >= blocks.length || blocks[i + 1].info !== 'expected') {
      reportFailure(label + ' is not followed by an ```expected block');
      i += 1;
      continue;
    }
    let want = blocks[i + 1].body;
    if (want.endsWith('\n')) want = want.slice(0, -1);
    const wantOut = want ? want + '\n' : '';
    let wantCode = 0;
    const exitMatch = /exit=(\d+)/.exec(info);
    if (exitMatch) wantCode = parseInt(exitMatch[1], 10);
    const result = Nifla.run(body, {
      args: ['Ada', 'Byron'],
      files: sharedStore ? store : {},
    });
    if (sharedStore) store = result.files;
    let ok = true;
    if (result.output !== wantOut) {
      reportFailure(label + ': output differs',
        '  expected: ' + JSON.stringify(wantOut) + '\n  got:      ' + JSON.stringify(result.output));
      ok = false;
    }
    if (result.exitCode !== wantCode) {
      reportFailure(label + ': exit code ' + result.exitCode + ', expected ' + wantCode,
        result.errorOutput ? '  error output: ' + JSON.stringify(result.errorOutput) : null);
      ok = false;
    }
    if (ok) {
      console.log('PASS ' + label);
      ran += 1;
    } else {
      failed += 1;
    }
    i += 2;
  }
  const failures = totalFailures - failuresBefore;
  console.log(bookFile + ' examples: ' + ran + ' executed and passed, ' +
    failed + ' executed and failed, ' + compileOnly +
    ' bare compile-only (noted), ' + failures + ' failure(s)');
  return ran;
}

const exampleCount = runExamples();
const primerCount = runBook('PRIMER.md', true);
const tutorialCount = runBook('TUTORIAL.md', false);

console.log('---');
if (totalFailures > 0) {
  console.log('WEB CORPUS: ' + totalFailures + ' failure(s)');
  process.exit(1);
}
console.log('WEB CORPUS PASS: interpreted suite ' + exampleCount + '/' + exampleCount +
  ', primer ' + primerCount + ' hosted examples, tutorial ' + tutorialCount + ' hosted examples');
