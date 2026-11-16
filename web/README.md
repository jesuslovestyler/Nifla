# Nifla on the web

`nifla.js` is the Nifla interpreter written in JavaScript, so a
Nifla program can run inside a web page. It is one
dependency-free file: it runs the same in a browser (where it
leaves a `Nifla` global behind) and under Node (where it can be
`require`d). The full documentation lives in the header comment
of `nifla.js` itself; this page is the short version.

## The API

```js
const result = Nifla.run(source, { args, files });
// result: { output, errorOutput, exitCode, error, files }
```

- `source` — the Nifla program, as text.
- `args` — the words `arguments()` hands the program (optional).
- `files` — the paper-store's starting papers: an object whose
  keys are file names and whose values are text, or a
  `Uint8Array` for a file held as bytes (optional).
- `output` / `errorOutput` — everything the program said, and
  everything it said on the error channel (`sayerr`, and a
  refusal's own words, which arrive as `"Line N: ..."`).
- `exitCode` — 0, the number `exitwith` left, or 1 when the
  program was refused.
- `error` — the refusal in plain words, `"Line N: ..."` shaped,
  or `null` when the program ran its course.
- `files` — the paper-store as the run left it, in the same
  shape it went in, so the host page can read back what the
  program wrote.

## The scope, honestly

This door runs the **hosted language** — the world the
Tutorial's Lessons 1–8 teach: `say`, `let`, numbers, text,
true/false and comparisons, `if`/`else`, `while`, `repeat`,
`for`…`in`, lists, objects, `make`/`give`, `attempt`/`if it
fails` (with `problem`), the whole toolbox (`length`, `part`,
`find`, `split`, `join`, `append`, `insertat`, `removeat`,
`sorted`, `fieldnames`, `removefield`, `makebytes`),
`arguments`, `sayerr`, `exitwith`, and the kind marks with
checked absence (`nothing`/`maybe`, with the checker's
narrowing on `== nothing` / `!= nothing`).

The pre-run checker is here in fact, not just in spirit: a
misspelled name, a wrong-kind tool argument, or a maybe-value
used as surely-there is refused **before** anything runs, in
the same plain words the Swift checker speaks. Runtime
problems are answered in the same plain words too, with line
numbers, and the runaway guards are the same: a million loop
passes, five hundred calls deep, sixteen megabytes in one
block of bytes.

**Not on this door:** the floor, bare metal, guests and
feathers, and the compiler. Those belong to real metal and to
`niflac`. A program that holds floor code is refused in plain
words saying so.

**Files:** a web page has no disk, so `readfile`, `writefile`,
and `readbytes` work on the in-memory paper-store above. A
name in the store is the whole address — there are no folders.
That is the one platform difference: on a real disk,
`writefile` can fail because a folder is missing; in the store
a write cannot fail that way, and every other file refusal
(a missing paper, a file that is not text, an oversized block)
speaks exactly as the Swift interpreter speaks.

## The proof

`run-web.sh` (in the repository root) runs the existing hosted
conformance corpus through this interpreter under Node and
diffs every program against the expectations the Swift suites
already record: the interpreted suite's 42 programs, every
hosted example in PRIMER.md, and every hosted example in
TUTORIAL.md. Floor examples are checked to be refused with the
exact floor refusal; bare-metal examples are compile-only on
every door and are noted in the output, never silently
skipped.
