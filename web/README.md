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

**Not on this door:** bare metal, guests and feathers, and
the compiler. Those belong to real metal and to `niflac`.
Floor code runs here — on a simulated desk, below.

**Files:** a web page has no disk, so `readfile`, `writefile`,
and `readbytes` work on the in-memory paper-store above. A
name in the store is the whole address — there are no folders.
That is the one platform difference: on a real disk,
`writefile` can fail because a folder is missing; in the store
a write cannot fail that way, and every other file refusal
(a missing paper, a file that is not text, an oversized block)
speaks exactly as the Swift interpreter speaks.

## The floor desk

Floor blocks run on a **simulated desk**: a small simulation
of the floor contract the Primer's Part 4 tells. The desk
keeps the sixteen registers, the flags the jumps read, and
four pieces of memory — the numbers handed in (where `r10`
points, `r11` counting them), the one block of bytes (where
`rbx` points, `r12` counting them — the very same bytes the
program holds, so what a block writes there stays written),
the answers area (`r13`, with `r14` holding the count of
extra answers), and a stack. The block's assembly is read
and carried out instruction by instruction, and what comes
back is what the contract says: the main answer, or the list
when the block wrote extra answers.

The desk covers the instructions Nifla's own books and tests
use: `mov`, `lea`, `push`, `pop`; `add`, `sub`, `imul`,
`mul`, `div`, `idiv`, `inc`, `dec`, `neg`, `not`; `xor`,
`and`, `or`, `cmp`, `test`; `shl`, `shr`, `sar`; `jmp` and
the condition jumps; `nop`, `cld`, `std`; and `syscall` —
the write call only (number 1), which writes to the
program's own output or error channel and answers with the
count, as the real call does; a write to a channel the
program does not hold answers −9, as the real call does.

The limits are named, never silent:

- A block using anything the desk does not cover is refused
  **before anything in the program runs**, in plain words
  naming the instruction — the same honesty as the compiled
  door's checker refusing what it can prove wrong.
- A block reaching for memory outside its desk is stopped
  with the reach named; on real metal it would land wherever
  it pointed.
- A division by zero, or one whose answer is too big to
  hold, stops the block, as the processor's fault stops a
  real program.
- A block that runs past ten million instructions is
  stopped, so a web page stays alive.
- Any other system call is refused, naming the call number:
  the desk is not a machine's system.

Registers the contract does not name start at zero and the
stack starts empty, so the desk is the same every run. The
desk is a learning simulation: the books' teaching about
real metal stands untouched, and a block that needs the
real thing is built with `niflac`, as the refusal says.

## The proof

`run-web.sh` (in the repository root) runs the existing hosted
conformance corpus through this interpreter under Node and
diffs every program against the expectations the Swift suites
already record: the interpreted suite's 42 programs, every
hosted example in PRIMER.md, and every hosted example in
TUTORIAL.md — floor examples included, run on the desk and
compared like the rest. Bare-metal examples are compile-only
on every door and are noted in the output, never silently
skipped.

`run-web-floor.sh` is the desk's own proof: the floor suite,
the checker's floor refusals, and the books' floor examples
against their recorded expectations, plus the desk's honesty
tests — the blocks it refuses, and the limits it names.
