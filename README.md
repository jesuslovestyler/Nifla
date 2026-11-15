# Nifla

**נפלא** — *nifla*: wonderful, marvelous.

Nifla is a programming language in its very first beginnings.

It is a name set in place on **November 13, 2026**, by Tyler Kovalevich of
[Cardnull](https://cardnull.com), for a language he intends to build one day
and give away: a language in the spirit of Swift — readable, plain in its
errors, kind to beginners — released into the **public domain**, so that
anyone, anywhere, can learn it and program whatever they want with it, free
forever, no permission asked and none needed.

## Why

Most programming languages are free to use but owned. Nifla is meant to be a
gift instead: a tool placed in the world's hands the way a bell is placed in
a tower — whoever hears it may use it. Learn it, build with it, teach with
it, make something for someone you love with it.

## The order of the work

This repository began as a name-stone. The sequence is settled and public:

1. **Cardnull OS first** — the operating system is being built now, in Swift,
   and it comes before everything else.
2. **Then Nifla** — designed slowly, out of everything the OS years teach,
   and only when the OS is finished.

On **November 14, 2026**, Tyler chose to open the design early and lay the
first stone — a small first slice of the interpreter, below — while the OS
work continues. The design he settled that evening: **one language with
three layers** — JavaScript's immediacy and objects, Swift's safety and
readability, and Assembly's reach to the processor, through a marked
low-level layer called the Floor. The full language still comes after the
OS; what is here is the first stone, laid in the open, in this repository.

## Stone 1 — the first interpreter

A small tree-walking interpreter, written in Swift, that runs Nifla's
first slice — the play mode. Today Nifla knows:

- Numbers (whole and decimal) and text in `"double quotes"`, with `//` comments
- `let name = ...` to make a variable, and `name = ...` to change it
- Arithmetic `+ - * /` with parentheses; `+` also joins text, and text joins with numbers
- Comparisons `== != < <= > >=`, and the values `true` and `false`
- `say ...` to print a value on its own line
- `if ... { ... }` and `if ... { ... } else { ... }`; variables made inside a block stay inside it
- Errors in plain words, naming the line and how to fix it — never a stack trace

Build and run:

```sh
./build.sh                      # makes ./nifla (needs a Swift compiler)
./nifla examples/hello.nifla    # run a program
./run_tests.sh                  # build, then check every example's output
```

A tiny program:

```nifla
say "Shalom"
let name = "Tyler"
say name
```

prints

```
Shalom
Tyler
```

Not built yet, on purpose: the compiler, objects, functions, and
the Floor. Those are later stones.

## Stone 2 — loops

Laid on **November 14, 2026**, the same evening as the first stone.
Nifla can now repeat itself, in two ways:

- `while ... { ... }` — runs the block again and again, checking the
  condition before each pass, and stops when the condition turns false
- `repeat N { ... }` — runs the block exactly N times; N is worked out
  once, before the loop starts, and must be a whole number, zero or more

How loops treat variables, kept simple: setting a variable inside a
loop changes the one outside it — that is how counting works — while a
variable made with `let` inside a loop's block is made fresh on every
pass and stays inside the block.

A kindness built in from the start: a loop that would run effectively
forever is stopped. After a million passes in one program, Nifla stops
the run and says so in plain words, naming the loop's line, instead of
hanging.

Still not built yet, on purpose: functions, objects, the compiler, and
the Floor. Those are the next rings.

## Stone 3 — functions

Laid on **November 14, 2026**, later the same evening. Nifla can now be
taught words of its own:

- `make name(...) { ... }` — makes a function. The names in the
  parentheses are the values it is handed each time it is called, and
  the block is what runs. Making a function is a line like any other:
  it takes effect when the program reaches it, so a function can be
  called from that line on
- Calling: `name(value, value)` — on its own line, when the call is
  for what the function does, or inside any expression, when it is for
  the value the function gives back
- `give ...` — hands a value back to whoever called the function, and
  ends the call there. A function that finishes without a `give` gives
  nothing back, so it can only be called on its own line; using its
  result in an expression is a plain-words error

How functions treat variables, kept the same as blocks: names made
with `let` inside a function stay inside it, and the values a function
is handed shadow same-named variables outside it. Setting an existing
outer variable from inside a function still reaches it, just as it
does from a block — that is how a function can keep a count.

A function may call itself — recursion — and like loops, it is
guarded: a call chain more than five hundred deep is stopped with a
plain-words error instead of crashing. Mistakes are plain words too:
calling a function that was never made (with a "Did you mean...?"
when a close name exists), giving it the wrong number of values
(saying how many were expected and how many were given), or using
`give` outside a function.

Tyler's own first function is among the examples —
`examples/hello-many.nifla`: every time it is called, it says hello
three times, a Stone 2 `repeat` loop living inside a function.

Still not built yet, on purpose: objects, the compiler, and the
Floor. Those are the next rings.

## Stone 4 — objects

Laid on **November 14, 2026**, later the same evening. The
JavaScript face of Nifla arrives: things with named fields, carried
around as one value.

- `{ name: "Tyler", years: 29 }` — an object literal: field names
  and values in braces, separated by commas. A field's value can be
  anything, including another object
- `person.name` — reading a field with a dot. Dots chain, so
  `person.home.town` reaches through an object held in a field
- `person.years = 30` — setting a field with a dot and an `=`.
  Setting a field the object doesn't have yet adds it; dots chain
  here too, so `person.home.town = "Greenville"` works
- Objects go everywhere other values go: into variables alongside
  numbers and text, and into functions, which read and set their
  fields. Two objects are `==` only when they are the very same
  object, not merely alike

Saying an object prints a readable listing of its fields, in the
order they were first written, with text values in quotes so they
can't be mistaken for numbers:

```nifla
let person = { name: "Tyler", years: 29 }
say person
```

prints

```
{ name: "Tyler", years: 29 }
```

One decision, stated plainly: **objects are shared by reference,
not copied** — the JavaScript way. `let b = a` makes `b` hold the
very same object as `a`, so `b.years = 30` changes what `a.years`
reads, and a function handed an object can change its fields for
whoever called it. The example `examples/describe.nifla` shows
this on purpose: its birthday function adds a year, and the year
stays added after the call.

Tyler's own example is `examples/tyler.nifla` — an object of Tyler
himself, in the shape he asked for ("Make an object of me"): his
name, his years, and his role, with a hometown added by setting a
field.

Mistakes are plain words, as always: reading a field an object
doesn't have (the error lists the fields it does have, and
suggests a close one — "Did you mean 'name'?"), reading or setting
a field on something that isn't an object, and naming the same
field twice in one object literal.

Honest limits: there is no way yet to remove a field, to ask an
object how many fields it has, or to loop over its fields; an
object that contains itself prints the self-reference as `...`
rather than listing forever; and fields are always written with
plain names — a field name can't be built out of text at run time.

Still not built yet, on purpose: the Floor. The compiler is the
next ring — Stone 5, below.

## Stone 5 — the compiler (first form)

Laid on **November 14, 2026**, later the same evening. Nifla gains
the Swift face's two gifts: a checker that reads a program before
it runs, and a compiler that turns it into a program that stands
alone.

**The checker** runs before anything else, in both `nifla` and
`niflac`. It walks the program in the order it would run, keeping
track of what it can prove about each variable's kind — number,
text, true/false, object — from literals and from `let` lines
whose value's kind is clear. It stops the program, in plain words
with the line named, when it can prove:

- a `+`, `-`, `*`, `/`, `<`, `<=`, `>` or `>=` whose two sides'
  kinds are both known and can never work together — adding a
  number and a true/false value, comparing text with a number
- a call to a function that is never made anywhere in the program
- a call whose number of values doesn't match the function's
- a variable used, or set, that no `let` has made

For the name-and-count mistakes it uses the interpreter's exact
words, so a program it stops reads just as it would have read
when the interpreter stopped it. Five small programs in
`checker-examples/` show each refusal.

**The compiler** is `niflac`:

```sh
./build.sh                       # makes ./nifla and ./niflac
./niflac examples/tyler.nifla    # makes ./examples/tyler, a native program
./examples/tyler                 # runs it — no interpreter involved
```

`niflac` runs the checker first; a refused program is not
compiled and leaves nothing behind. When the checker is content,
niflac translates the program into Swift and compiles that,
together with a small runtime (`runtime/NiflaRuntime.swift`)
that mirrors the interpreter's values and rules, into a native
program beside the source (or at the path `-o` names). The whole
Stone 1–4 language compiles — loops with their runaway guard,
functions with their call-depth guard, objects shared by
reference — and a compiled program behaves exactly as the
interpreter would have run it: same output, same plain-words
errors, same guards. The Swift it was made from is kept beside
the program (as `tyler.swift`) for anyone who wants to read it.

The proofs, in `run-compiled.sh`, compile every one of the 25
examples and check the compiled behavior against the same
expected files the interpreter is checked against; check that
both tools refuse every checker example; and copy one compiled
program alone into an empty folder and run it there, to prove it
stands alone:

```sh
./run_tests.sh      # the interpreter: 25 passed, 0 failed
./run-compiled.sh   # the compiler and checker: 36 passed, 0 failed
```

Honest limits, stated plainly:

- The checker proves only what it can see clearly. A kind that
  flows out of an object, out of a function, or into a function
  as a handed value can't be proven from the writing, so the
  checker stays silent about it and the run-time checks — the
  interpreter's, or the compiled program's own — remain the
  guard, in the same plain words. A mistake inside a branch that
  would never run is still caught when the checker can prove it;
  the checker reads the whole program, as Swift's compiler does.
- Because a function can set variables outside itself, the
  checker forgets every kind it thought it knew whenever a
  function is called. Better silent than wrong.
- Compiling takes about a second a program — the Swift compiler
  does the heavy work, and this first form doesn't hurry it.
- The translation goes through Swift. There is no Floor yet —
  Nifla doesn't talk to the processor directly — and no
  self-hosting yet: the checker and compiler are written in
  Swift, not in Nifla. Those are later stones, in the settled
  order: the compiler first, then the Floor.

## Stone 6 — words and lists

Laid on **November 14, 2026**, later the same evening. Nifla gains
its words and its lists — and, quietly, the tools the
self-hosting stone will be built from.

**Lists** are values in order, written in square brackets:

```nifla
let prices = [3, 5, 2]
say prices[0]          // 3 — items are numbered from 0
prices[1] = 6          // set an item by its number
append(prices, 9)      // add an item at the end
say length(prices)     // 4
for price in prices {  // walk the list, one item at a time
    say price
}
```

A list can hold anything — numbers, text, objects, other lists —
and lists are shared the way objects are: hand a list to a
function and the function works on the same list, not a copy. A
`for` loop walks the items as they stood when the loop began, so
adding items inside the loop doesn't stretch it. The loop's name
is fresh on every pass and stays inside the loop. Saying a list
prints its items in brackets, with text items in quotes so they
can't be mistaken for numbers.

**Text** can be worked with, not just joined: `text[0]` takes one
character (a small piece of text of its own), and a `for` loop can
walk a piece of text character by character. Text itself never
changes once it is made — trying to change one character says so
in plain words; to change text, build the new text and set the
variable to it.

**Nine built-in tools** come with every program, with no `make`
needed — and a function can't be made with a tool's name:

| Tool | What it does |
| --- | --- |
| `length(value)` | How long: characters in text, items in a list, fields in an object |
| `join(list, separator)` | A list's items as one piece of text, with the separator between them |
| `split(text, separator)` | Text broken into a list of pieces, split at the separator |
| `part(text, start, count)` | A piece of text: `count` characters starting at character `start` |
| `find(text, piece)` | Where a piece first appears in text (a character number), or −1 when it isn't there |
| `append(list, value)` | Adds a value to the end of a list, and gives the list back |
| `readfile(path)` | The whole of a text file, as text |
| `writefile(path, text)` | Writes text to a file (replacing what's there); gives back how many characters it wrote |
| `arguments()` | The words the program was started with, after its own name, as a list of text |

The **checker** knows the tools, too. It knows what kind each one
gives back — so `length("abc") + true` is refused before the run,
like any other bad adding — it refuses a call with the wrong
number of values in the run's own words, and when a handed
value's kind is plain to see and can never work for the tool —
`length(29)`, or `join` handed text instead of a list — it stops
the program before anything runs, in plain words. Three cases in
`checker-examples/` show the tool refusals.

The proofs grew with the stone: eight new examples (words,
joinwords, shopping, letters, notefile, args, and two plain-words
failures — a list asked for an item it doesn't have, and an
attempt to change one character of text) pass under both tools:

```sh
./run_tests.sh      # the interpreter: 33 passed, 0 failed
./run-compiled.sh   # the compiler and checker: 50 passed, 0 failed
```

Honest limits of Stone 6:

- There is no way to take an item *out* of a list, put one in the
  middle, or sort a list yet. `find` searches text, not lists.
- Text operations count **characters**, the way a person counts —
  not bytes.
- `split` refuses to split by an empty piece of text.
- Files are whole text files only: read all at once, written all
  at once (there is no adding onto the end of a file), as UTF-8
  text. No binary files, and no asking the person at the keyboard
  for input yet.
- Item numbers are whole numbers starting at 0. Two lists are
  `==` only when they are the *same* list, the way objects
  compare — there is no item-by-item comparing yet.

Still not built yet, on purpose: the Floor, and Nifla written in
Nifla. Those are the next rings, in the settled order.

## Stone 7 — the Floor (first form)

Laid on **November 14, 2026**, later the same evening. The third
face of Nifla arrives: a marked block that talks to the processor
directly, in the processor's own instructions.

```nifla
let quotient = floor {
    mov rax, 100
    mov rcx, 7
    xor rdx, rdx
    div rcx
}
say quotient        // 14
```

A floor block is written `floor {` on its own line, then the raw
instructions — x86-64, in Intel syntax — one per line, exactly as
written, until a line holding only `}`. The lexer takes those
lines whole; they are never read as Nifla. A floor block is an
expression: it **gives back a number** — whatever its instructions
leave in the processor's return register, `rax`, when they finish.
It can stand anywhere a value can, or on its own line, run for
what it does.

The contract, plainly: the instructions must leave the stack as
they found it and preserve the registers a called function is
expected to preserve (`rbx`, `rbp`, `r12`–`r15`); `niflac` adds
the `ret` itself, so a block doesn't write one; and labels inside
a block should be local numeric ones (`1:`, jumped to with `1b` /
`1f`), because every block in a program is assembled into one
file.

**Only compiled programs run floor code.** The interpreter
refuses a program that holds any floor block — before anything
runs, even a block on a path the run wouldn't take — in plain
words: floor code runs only when compiled. The **checker** treats
a block as opaque (the instructions are the processor's
business), but it verifies the block is well-formed: an empty
block is refused before the run, a block that is never closed is
refused while the program is being read, and the checker knows a
block gives back a number, so `floor { ... } + true` is refused
like any other bad adding.

When `niflac` compiles a program with floor blocks, it wraps
each block as a small assembly function, assembles them with the
machine's C toolchain, and links them into the program. The
assembly is kept beside the program (as `name.s`), next to the
generated Swift, for anyone who wants to read it.

The proofs, in `floor-examples/` and Part 4 of `run-compiled.sh`:
`floorwrite` writes "Floor!" to the screen through a raw system
call — something the high-level language cannot do — and reports
the 7 bytes written, between ordinary `say` lines; `floordiv`
uses the processor's `div` instruction and hands back both its
quotient (14) and, from a second block, its remainder (2) — an
answer Nifla's own arithmetic never touches. Each is checked both
ways: the interpreter refuses it with exactly the recorded words,
and the compiled program runs it and prints exactly the recorded
output.

```sh
./run_tests.sh      # the interpreter: 33 passed, 0 failed
./run-compiled.sh   # the compiler, checker, and Floor: 58 passed, 0 failed
```

Honest limits of Stone 7, stated plainly:

- This is the Floor's **first form, on this machine**: Linux on
  x86-64. The instructions are this processor's; another
  processor (like the ARM boards Cardnull plans) will need its
  own floor dialect when its time comes.
- It is the **seed of kernel work, not a kernel**. A floor block
  runs inside an ordinary program, with the operating system
  still underneath it. Talking to hardware with nothing beneath
  is the Cardnull OS road, not this stone.
- A floor block **can't be handed Nifla values yet**: it starts
  from the processor's registers alone, and it gives back exactly
  one number. Whole numbers are exact up to 2⁵³, the way all
  Nifla numbers work.
- Floor code is raw access, with raw consequences: an instruction
  that faults — dividing by zero, touching memory it shouldn't —
  takes the whole compiled program down with it, and no
  plain-words error can catch it. The checker can't see inside a
  block, and the assembler is the only judge of the instructions.
  That danger is what the marking is for: the Floor is fenced and
  labeled, never mixed silently into ordinary code.

Still not built yet, on purpose: Nifla written in Nifla. That is
the next — and last — ring of this road.

## Stone 8 — self-hosting: the interpreter, in Nifla

The last ring of this road: an interpreter for the whole Nifla
language, written in Nifla itself — `selfhost/nifla-in-nifla.nifla`,
about 2,500 lines. It reads a program with `readfile`, takes it
apart character by character, builds the program's shape out of
objects and lists, and runs it — every value the interpreted
program holds is itself a Nifla object (`{ kind: "number", num: … }`),
every scope a pair of lists searched by name, because Nifla field
names can't be built from text while a program runs. It speaks the
Swift interpreter's own words throughout: the same plain-words
errors, the same "Did you mean" kindness (the same edit-distance
rule, re-implemented), the same loop and call guards counted the
same way, the same refusal of floor code before anything runs.

Compiled with `niflac`, it becomes a standalone program that runs
Nifla programs with **no Swift interpreter involved at run time at
all**. The proof is `./run-selfhost.sh`: it compiles the self-host
once, then runs the example suite through the compiled binary and
compares every program's output against the Swift interpreter's
expected output, byte for byte.

**What it verifiably runs: 31 of the 33 examples** — every success
example, and eight of the ten error examples, with the error words
matching byte for byte (`badcall`, `badindex`, `badrepeat`,
`broken`, `missing`, `nofield`, `notobject`, `textchange`). In
other words, the full current language: words and text, lists,
objects, functions and recursion, all the loops, all nine built-in
tools, files, program arguments, and floor refusal.

**What it does not run — the two guard examples, honestly:**

- `endless` (a function calling itself forever). Each call the
  interpreted program makes costs several calls inside the
  self-host, so the *host's* limits give out first: under the
  Swift interpreter the host's own five-hundred-call guard stops
  it, naming a line inside `nifla-in-nifla.nifla`; compiled, the
  real processor stack overflows and the program crashes before
  either guard can speak. The interpreted program's own guard
  message is never reached.
- `forever` (a loop that never ends). Each pass of the
  interpreted loop also spends passes of the host's own loops,
  so the host's million-pass guard speaks first — again naming
  a line inside the self-host, not the program's line 3.

Both of these stood from Stone 8 through Stone 13, and
**Stone 14 closed them both** — the run was rebuilt as a
machine on a heap-held stack of frames, and the two programs'
own guards now speak first, in their own words, at their own
lines. See Stone 14's section below; the words above are the
record as it stood when this section was written.

**Honest limits:**

- There is **no static checker inside the self-host** — it checks
  as it runs, the way the interpreter does. That is enough for
  every example's error words to match, because the Swift tools'
  runtime words and checker words agree wherever both can speak;
  but a program the checker would refuse *before* running (say,
  adding a number to a true/false value it can prove) is refused
  by the self-host only when the run reaches it.
- An interpreted program's error is **said aloud to stdout**, and
  the self-host finishes normally; the Swift tools print errors
  to stderr and exit with a failure. The words match byte for
  byte; the channel differs, because a Nifla program has no way
  to write to stderr or to choose its exit code.
- A file that can't be read or written *inside* an interpreted
  program surfaces as the self-host's own host error (with a
  line inside `nifla-in-nifla.nifla`), because Nifla has no way
  to catch an error and carry on. The words a missing file gets
  are the host's, not a mirrored message.
- Names in the self-host's reader are ASCII letters, digits, and
  `_`; the Swift reader also accepts other letters (é, say).
  Numbers are read exactly for the digits the suite uses; a
  number with hundreds of digits is read approximately, where
  the Swift reader reads it in full.
- The self-host is slower — it is an interpreter interpreting.
  The suite runs in about a second compiled; a million-pass
  interpreted loop takes the better part of a minute.

That was the road's end, as far as it was drawn up to that
point: the interpreter, the checker, the compiler, words and
lists, the Floor — and the language running itself. The road
did not stay ended; the next three stones follow.

## Stone 9 — the Floor gets hands

Laid on **November 14, 2026**, later still the same evening, at
Tyler's word to walk the next three stones. Until now a floor
block started from the processor's registers alone and gave
back exactly one number. Now the friendly side and the Floor
can hand work back and forth.

**A block of bytes** is a new kind of value: a fixed stretch of
raw memory, made with `makebytes(count)` — that many bytes, all
zero to start. Its bytes are read and written by number, the
way a list's items are (`data[0] = 72`, `say data[0]`), a byte
being a whole number from 0 to 255; `length` measures it, and a
`for` loop can walk its bytes as numbers. Saying one prints its
numbers in a shape no list can be mistaken for:
`bytes(72, 101, 108, 108, 111)`. A block is shared by
reference, the way objects and lists are — which is what lets
the next part work.

**Handing values to a floor block** is written the way a call
is: `floor(100, 7) { ... }`. When `niflac` wraps a block, it
lays out a desk for the block's instructions before they run:

- **r10** points to the handed whole numbers, in order — the
  first at `[r10]`, the second at `[r10 + 8]`, and so on — and
  **r11** says how many there are
- **rbx** points to the first byte of the one block of bytes
  the block was handed (0 when it was handed none), and
  **r12** says how many bytes it holds
- **r13** points to a results area with room for eight numbers,
  and **r14** starts at 0

The block gives back what it always did — the number in `rax`
— and, when it has more to say, it writes up to eight extra
numbers at `[r13]`, `[r13 + 8]`, … and sets `r14` to how many
it wrote; then the block gives back **a list**: the `rax`
number first, then the extras in order. The wrapper preserves
the registers a called function must preserve and tidies up
afterwards, as before; inside the block, `rbx`, `r12`, `r13`
and `r14` are the desk — overwrite them and the desk is lost,
and `r14` must hold the extra-answer count when the block
ends.

The proofs, in `floor-examples/`: `floorbytes` makes a block
of bytes, writes "Hello" into it as numbers, hands the very
same memory to a floor block that adds one to every byte, and
reads "Ifmmp" back; `floorsum` hands 100 and 7 in and gets the
divide's quotient *and* remainder back as the list `[14, 2]`.
The **checker** checks what a block is handed: a handed value
whose kind is proven to be anything but a number or a block of
bytes is refused before the run, a second block of bytes is
refused, and `makebytes` itself is checked like every tool
(three cases in `checker-examples/`). The interpreter still
refuses any program holding floor code, exactly as before.

```sh
./run_tests.sh      # the interpreter: 34 passed, 0 failed
./run-compiled.sh   # the compiler, checker, and Floor: 69 passed, 0 failed
```

Honest limits of Stone 9:

- A floor block can be handed **whole numbers only** — a
  number with a part after the point is refused in plain words
  when the block is reached (the desk is whole-number
  registers), and at most **one** block of bytes. Text, lists,
  and objects can't cross the desk; a block of bytes is the one
  stretch of shared memory.
- The results area holds **eight** extra answers; a block that
  sets `r14` higher is read as eight. What a block gives back
  can no longer be proven by the checker — it may be a number
  or a list — so the checker stays silent about it and the
  run's own checks guard its use, as with values out of
  objects.
- A block of bytes is at most 16,777,216 bytes (16 MiB), and
  its size never changes once made — there is no growing or
  shrinking it, and no reading a file into one yet: files are
  still whole text, as Stone 6 left them.
- The desk is this machine's desk: Linux on x86-64, the same
  honest limit Stone 7 stated. Floor code is still raw access
  with raw consequences — an instruction that faults takes the
  whole compiled program down, and a block that writes outside
  the memory it was handed is writing outside the language's
  protection entirely. That is what the marking is for.

## Stone 10 — a grown-up voice

Laid on **November 14, 2026**, the same evening, second of the
three. Until now a Nifla program that met a problem had exactly
one move: stop, and let the interpreter say what happened. And
everything a program said went to one place, with one parting
number it couldn't choose. This stone gives programs a voice
like a grown-up tool's: catch a problem and carry on, speak to
the error channel, and choose the number you leave behind.

**Catching a problem** is written in plain words:

```
attempt {
    let notes = readfile("notes.txt")
    say notes
} if it fails {
    say "No notes yet — starting fresh."
}
```

The first block runs in its own scope, like any block. If a
problem stops it, the second block runs instead, also in its
own scope, with the problem's words held in a variable called
**`problem`** — the message itself, without its "Line N:" —
and the program carries on after the whole construct. A `give`
inside either block gives from the function as usual; only
Nifla problems are caught. When nothing goes wrong, the
recovery block simply doesn't run. (`examples/attempt.nifla`
catches a missing file and a division by zero, and carries
on.) An `attempt` must have its recovery block — there is no
form that catches a problem and says nothing about it.

**Two new tools speak with the grown-up voice:**

- `sayerr(value)` — says a value's spoken form on the
  **error channel**, the way `say` speaks to the screen, and
  gives back how many characters it wrote, the newline
  counted.
- `exitwith(code)` — ends the program at once and chooses its
  **parting number**, a whole number from 0 to 255: 0 for
  success, anything else for the kinds of failure a program
  knows how to name.

A third small suite, `voice-examples/`, proves the three
channels together — screen, error channel, and parting
number, interpreted and compiled — under `./run-voice.sh`,
including a program that catches a missing file, reports it
on the error channel, and leaves with 2.

**Working on what's already made** — five more tools, all in
the one shared table the interpreter, the compiled runtime,
the checker, and now the self-host all keep:

- `removeat(list, index)` — takes the item at that place out
  of the list and **gives the item back**
- `insertat(list, index, value)` — puts a value into a list
  at that place (the end is a fair place), and gives the list
- `sorted(list)` — gives back a **new list**, sorted: all
  numbers, smallest first, or all text, in the machine's
  character order (capitals before small letters, as the
  characters themselves are numbered). A mixed list, or one
  starting with anything else, is refused in plain words. The
  list handed in is left as it was
- `fieldnames(object)` — the object's field names, as a list
  of text, in the order they were made
- `removefield(object, name)` — takes a field out of an
  object and **gives its value back**; a field that isn't
  there is the usual missing-field problem

(`examples/surgery.nifla` exercises all five.) The checker
knows each tool's shape as it knows every tool's, and checks
`attempt` the way it checks `if`: both blocks are checked
from the state before, `problem` is known text in the
recovery block, and what follows sees the merge.

**The self-host caught up — both of its Stone 8 differences
are closed.** The interpreter written in Nifla now reports an
interpreted program's problems on the error channel and
leaves with 1 (2 when the program file itself can't be
opened), exactly as the Swift interpreter does; and a
`readfile` or `writefile` failing inside the program it runs
is caught with `attempt` and re-said with the program's own
line number, instead of escaping as the self-host's own
error. `./run-selfhost.sh` now compares all three channels,
the way `run_tests.sh` rules them. The self-host also learned
Stone 9's `makebytes` and blocks of bytes with this stone —
**owning Stone 9's one unfinished edge: for that one stone
the self-host was behind the hosted tools**, and
`examples/bytebox.nifla` was the example it couldn't run. It
runs it now.

```sh
./run_tests.sh      # the interpreter: 36 passed, 0 failed
./run-compiled.sh   # the compiler, checker, and Floor: 71 passed, 0 failed
./run-voice.sh      # the grown-up voice, three channels: 6 passed, 0 failed
./run-selfhost.sh   # the interpreter in Nifla: 34 passed, 0 failed (of 36)
```

Honest limits of Stone 10:

- `attempt` catches **Nifla problems only** — the plain-words
  errors the language itself raises. A floor instruction that
  faults in a compiled program still takes the whole program
  down; there is no catching that, and this stone doesn't
  pretend otherwise.
- `problem` holds the message **without** its line number —
  the words alone. A program that wants the line must keep
  its own count; the message text is what it is.
- `exitwith` codes are 0 to 255 because that is what the
  system keeps of a parting number; a bigger or part number
  is refused in plain words.
- `sorted` orders text by the characters' own numbers, so
  capitals sort before small letters and the order is the
  machine's, not a dictionary's.
- Through the self-host, `makebytes` is bounded by the
  host's own loop guard (a million passes shared across the
  whole run), so a block near the hosted 16 MiB cap can't be
  made there; the hosted tools keep the full cap.
- The two self-host exclusions from Stone 8 stood when this
  section was written, for the measured host-guard reasons
  recorded there, and nothing in this stone was bent to
  change that. **Stone 14, later the same evening, closed
  them** — see its section below.

## Stone 11 — first bare metal

Laid on **November 14, 2026**, the same evening, last of the
three. Every program Nifla has ever made stood on something:
the interpreter, or a compiled binary carrying the Swift
runtime and the hosted runtime file, on Linux. This stone
takes the ground away.

```
niflac --bare program.nifla [-o out.elf]
```

compiles a **restricted subset** of Nifla into a freestanding
binary with no operating system and no runtime underneath —
the compiler emits x86-64 assembly itself (the Swift-codegen
path cannot do this; its output carries Swift with it), and
the assembly is kept beside the binary as `.s`, for reading.

**The bare subset**, enforced by a validator that runs after
the ordinary checker and refuses anything outside it, in
plain words, before anything is built:

- **whole numbers** — a number with a part after the point,
  or too big for the machine, is refused; division gives the
  **whole quotient** (`7 / 2` is 3 there — a real difference
  from hosted Nifla, named here on purpose)
- **text** as literals and variables: held, measured with
  `length`, compared with `==` and `!=`, and handed to a
  floor block. It cannot be joined, split, or searched —
  there is no one there to own new text
- **true and false**, as 1 and 0
- `let` and setting variables, `if`/`else`, `while`, `repeat`
- `make` and `give`, with recursion; values travel in the
  processor's registers, up to six words' worth per call
  (a piece of text takes two)
- **floor blocks** with the Stone 9 desk — r10/r11 the handed
  numbers, the one piece of text on the memory side (rbx/r12)
  — except **r13 is 0: there is no results desk**, so a bare
  floor block gives back only its `rax` number

Everything else is refused in plain words: `say`, objects,
lists, blocks of bytes as values, files, `for`, `attempt`,
and every built-in tool except `length`. A value's shape —
number, text, or true/false — must be one thing everywhere
it is used and handed; the validator pins shapes down from
uses and calls and refuses a clash. (The ordinary checker
runs first, with its one floor rule following the target:
on bare metal the desk takes text, so text handed to a
floor block is allowed there and only there.)

**What the binary contains**: a multiboot-1 header; a 32-bit
stub that sets up a stack, builds identity page tables (2 MiB
pages covering the first 1 GiB), enables PAE and long mode,
loads a small GDT, and steps into 64-bit code; the program —
its functions and statements as machine code, its text as
bytes in read-only data, its floor blocks as raw functions
behind the desk; and a halt loop for an ending. It is linked
at 0x100000 and repackaged in a 32-bit ELF shell, the form
QEMU's built-in multiboot loader accepts (every address is
below 4 GiB, so nothing is lost; GRUB reads either form).
The two runaway guards keep their numbers — a million loop
passes, five hundred nested calls — but on bare metal they
**halt the machine**: there is no one to speak to.

**The proof** is `bare-examples/nifla-bare.nifla`, run by
`./run-bare.sh`: the high level builds the number 15 with a
loop (15 is also 0x0F, white on black), chooses the text
"Nifla runs on bare metal" with an `if`, and hands word and
number to a floor block that writes the word to the screen's
memory at 0xB8000 with the number as each letter's color
byte; a second call writes "It works" on the next row, at a
cell worked out by a function. The script boots the binary
headless in QEMU and reads the VGA text buffer back through
the monitor; both rows must begin with the words in
`bare-examples/nifla-bare.screen`. It prints PASS — and it
does.

```sh
./run-bare.sh   # bare metal: PASS — the words are on the emulated screen
```

Honest limits of Stone 11:

- This is a **first proof that a kernel can be written in
  Nifla — it is not a kernel**. There are no interrupts, no
  keyboard or any input, no memory management beyond the
  one identity map, no drivers, and nothing to do after the
  program's last line but halt. The screen is written by
  hand, from a floor block, the way this bench's Cardnull
  work writes it.
- A problem on bare metal is **silent**: a faulting
  instruction, a division by zero, or a tripped guard stops
  the machine (or restarts it) with no words at all. Plain
  words need a speaker, and there isn't one down there —
  the validator's refusals before the build are the only
  plain words bare metal gets.
- Division gives the whole quotient, a negative `repeat`
  count halts instead of being refused in words, and a
  function that never `give`s hands back 0 — three named
  differences from hosted Nifla, all consequences of there
  being no runtime to speak or to hand back "nothing".
- One machine only: x86-64, booted the multiboot way, in
  QEMU on this bench (the script uses the bench's extracted
  QEMU 10 through its loader, or `$QEMU` when set). The ARM
  edition Cardnull dreams of would need its own floor, its
  own boot, and its own stone.

## Stone 12 — bare metal learns to listen

Laid on **November 14, 2026**, the same evening, first of the
next three. Stone 11's machine could speak — after a fashion,
through a floor block and the screen's memory — but it could
not hear, and it had no sense of time. This stone gives it
both.

**What the binary now carries**: before the program's first
line runs, the stub builds an **interrupt table** (256 doors)
and loads it, **remaps the two interrupt controllers** (the
PIC pair) so hardware interrupts arrive at doors 32 and up
instead of colliding with the processor's own exceptions,
**sets the timer chip (the PIT) ticking a hundred times a
second**, drains any byte the firmware left in the keyboard's
buffer, and switches interrupts on. Every door but two leads
to a stub that simply returns. The two that work:

- **the timer** (door 32): each knock adds one to a counter
  the program can read, and the controller is told "seen"
- **the keyboard** (door 33): the scancode waiting at the
  keyboard's port goes into a **ring buffer** of 64 bytes the
  interrupt fills and the program empties

**Three new tools**, bare-only — they exist on no other
target, and the checker knows them only when it checks for
bare metal (on hosted targets the names are simply unknown,
as they were before):

- `ticks()` — the number of timer knocks since the machine
  started, a hundred a second
- `readkey()` — the next scancode from the keyboard buffer,
  or 0 when no key is waiting. Scancodes are the keyboard's
  own numbers (set 1): a key pressed gives its make code,
  released gives the same number plus 128. Turning codes
  into letters is the program's own work, in Nifla
- `waittick()` — sleeps the processor until the next
  interrupt (the timer's, at the latest) and hands back the
  tick count, so a waiting program rests instead of spinning

**The proof** is `bare-examples/nifla-listen.nifla`, run by
`./run-bare-input.sh`: the program writes "Ticks: " on the
screen's third row and keeps the tick count written beside
it (a floor block works the digits out), echoes every letter
key it hears onto the first row, and sleeps between knocks.
The script boots it headless, reads the count twice through
the monitor and requires it to have grown, then types the
word **nifla** with the monitor's `sendkey` and requires the
first row to begin with "nifla". It prints PASS — and it
does.

```sh
./run-bare-input.sh   # bare metal: PASS — the timer ticks and the keyboard is heard
```

Honest limits of Stone 12:

- **Interrupts are truly interrupt-driven for input**: the
  keyboard's knock fills the ring the moment a key is
  pressed, whether the program is looking or not. What the
  program does is poll the ring — the honest shape of a
  first input path: nothing is lost while the program is
  busy (up to the ring's 64 bytes; a byte arriving at a full
  ring is dropped, the oldest news kept), and `waittick()`
  means the polling costs the processor nothing.
- **One keyboard, set-1 scancodes, letters only in the
  proof.** The program's table covers the lowercase letters
  and space. Key releases are seen (make code + 128) and the
  proof program ignores them; there is no shift or caps-lock
  state, no key repeat handling, and the extra byte that
  extended keys (arrows, and friends) send first isn't
  tracked — such a key's second byte could be mistaken for
  a plain key's code. The mouse and every other device
  remain unheard.
- Doors other than the timer's and the keyboard's return
  silently — including the processor's own exception doors,
  where returning means trying the same instruction again.
  A fault on bare metal is still silent, as Stone 11 said;
  it now may spin instead of halting, which is no more
  informative.
- The timer is the PIT on purpose: it is the clock every PC
  has and the simplest honest one. Its hundred-a-second is
  1193182 ÷ 11932 ≈ 99.99 — near enough that the README
  says "a hundred", and the count is a count of knocks, not
  a clock on the wall.

## Stone 13 — bare metal learns to remember

Laid on **November 14, 2026**, the same evening, second of
the three. Stone 11's machine lived in a fixed little room:
a 16 KiB stack, its words in registers and frame slots, and
not one byte more. This stone opens the house.

**The map.** The multiboot header now asks the loader for
memory information (flag bit 1), and the stub keeps the
loader's map pointer before anything can overwrite it. At
start-up a short walk of the **multiboot memory map** adds
up every usable stretch into a total, and finds the usable
stretch the program itself sits in: everything from the
program's end to that stretch's end is the heap. One new
bare-only tool reads the total:

- `memorysize()` — the usable memory of the machine, in
  bytes, as the loader's map reports it

**Blocks of bytes came to bare metal.** `makebytes` — a
hosted tool since Stone 9 — now works there too, backed by
a **bump allocator** over the heap: each block takes the
next slice, its size rounded up to a whole 16 bytes, and
the slice is **zeroed** before the program sees it. A block
is the same two words as a piece of text — an address and a
count — so it travels everywhere text travels: into
variables, through functions, and across a floor block's
desk on the memory side (a block and a text now share that
one side; a floor block takes one or the other). With the
value came its manners: `length` measures it, `block[i]`
reads a byte, `block[i] = n` writes one. A pick outside the
block, a stored value that isn't a byte (0–255), a request
past the heap's end, or a block past the hosted cap of
16 MiB **stops the machine** — bare metal's silent answer,
never a quiet corruption.

**The proof** is `bare-examples/nifla-memory.nifla`, run by
`./run-bare-memory.sh`, which boots the machine with a
distinctive **96 MiB**: the first row must read "Memory
total: " and the number `memorysize()` gave, in the band
(94 MiB, 96 MiB] — the map's usable sum sits a little under
the machine's size because the firmware's reserved
stretches are not usable (measured on this bench:
100,137,984 of 100,663,296). The second row must read
"Bytes OK": a **4 MiB block** — far bigger than any buffer
the machine code carries — was filled with a repeating
pattern by a floor block, verified byte by byte with zero
mismatches, and spot-checked from the Nifla side, length
included. It prints PASS — and it does.

```sh
./run-bare-memory.sh   # bare metal: PASS — the map is read and bytes live in real memory
```

Honest limits of Stone 13:

- **The allocator never frees.** Bump allocation is the
  honest first form: memory is handed out in order and
  never taken back, so a program that makes blocks forever
  fills the heap and then stops the machine at the next
  request. There is no free list, no reuse, no compaction —
  those are later stones' work, if they come.
- **The heap is one stretch**: the usable region the
  program itself was loaded into. Usable memory elsewhere
  in the map (below 1 MiB, or in any higher stretch) counts
  toward `memorysize()` but is not handed out.
- `for` still can't walk a block of bytes — `while` and a
  counter do that work — and two blocks can't be compared,
  added, or joined; a byte at a time, or a floor block, is
  the way.
- The map is trusted as the loader wrote it. On this bench
  the loader is QEMU's multiboot loader and the map is its
  e820; a loader that hands over no map leaves the total at
  0 and the heap empty, and the first `makebytes` stops the
  machine.

## Stone 14 — the last two fall

Laid on **November 14, 2026**, the same evening, third of
the three. Since Stone 8, the self-hosted interpreter —
Nifla written in Nifla, compiled by niflac — ran every
example in the suite except two, and the two were the guard
examples: `endless`, a function calling itself, and
`forever`, a loop that never ends. Each is supposed to be
stopped by the language's own kindness limits, speaking in
the program's own words at the program's own line. The
self-host never let them speak: it ran a program by calling
itself, one host call inside another for every call of the
program's (some six host calls for one of the program's, by
measurement), so the host's own five-hundred-call guard —
or, compiled, the real processor stack — gave out around
depth eighty, long before the program's depth guard; and an
endless loop's passes spent the host's loop passes on top of
what starting up had already spent, so the host's
million-pass guard spoke first, naming a line inside
`nifla-in-nifla.nifla` instead of the program's line 3.

**The run is a machine now.** The self-host's interpreter
section was rebuilt on an explicit stack of **frames held
in a plain list** — heap, not call stack: a frame for each
block being run, each statement waiting on a value, each
value being gathered piece by piece, and each call gathering
its handed values or running its function's body. A driver
takes one small step at a time — start a frame, hand a
finished value to the frame waiting under it, or unwind:
an error travels up the frames until an `attempt` frame
catches it, and a `give` travels up until the call frame it
leaves turns it into the call's value, stepping the depth
count back down on every road out. A program's calls push
frames now, never the host's stack, so the depth a program
can reach is bounded by **its own five-hundred guard and by
memory** — the way the Swift interpreter bounds it. The
driver takes up to thirty-two steps per pass of its own
loop, so the host's million-pass guard measures the
machine's work in coarse units; a program's loop passes are
counted by the same `tickLoop` as ever, in the program's own
units and no one else's.

Three honest frugalities keep the machine quick enough to
be useful, none of which changes what anything means: a
value that needs no gathering — a number, a piece of text,
a true/false, a variable's contents — is handed over at
once instead of taking a frame round-trip; a block with no
statements in it is finished the moment it is laid down,
since an empty block's outcome is always the same; and a
**waiting loop** — a loop whose body holds no statements,
which can change nothing and call nothing — runs its passes
in a tight counting loop of its own, eight passes to a turn
(the host's guard counts turns; the program's counts
passes), with a `while`'s condition worked out once when it
needs no gathering, since an empty body cannot change it.
The moment a pass needs the machine, the ordinary road
takes over in exactly the state the step-by-step road would
have left.

**The proof** is `./run-selfhost.sh`, which now runs **all
thirty-six examples: 36 passed, 0 failed** — the exclusions
are gone from the script, and `endless` and `forever` are
compared on all three channels (standard output, standard
error, parting number) like every other example. `endless`
speaks its own words — "more than five hundred functions
deep", at its line 4 — in well under a second. `forever`
speaks its own — "ran more than a million times", at its
line 3 — in about nineteen seconds on this bench, most of
the thirty the harness allows it: a million counted passes
is the work the example is. The Swift interpreter, the
compiled runtime, and the checker were not touched, and no
guard's number changed anywhere: the hosted suites stand
where they stood (36/36 interpreted, 71/71 compiled, 6/6
voice), and the bare proofs still pass.

Honest limits of Stone 14:

- **The machine is slower than the recursion it replaced**
  for ordinary work — measured on this bench, a twenty-
  thousand-pass counting loop takes about fifteen seconds
  through the machine against about six through the old
  recursive run. Each step is a journey through the compiled
  host's dynamic runtime, and frames cost more than calls
  did. Correctness was bought with speed, knowingly.
- **The waiting road is narrow.** It covers loops whose
  bodies hold no statements — and, for `while`, a condition
  that needs no gathering. A million-pass loop whose body
  does work, or whose condition has pieces, still runs at
  machine-step speed (some fifty microseconds a step on
  this bench), so a million such passes would take minutes
  through the self-host. `repeat` with an empty body takes
  the waiting road too; `for` does not, since each of its
  passes needs a scope and an item of its own. The Swift
  interpreter runs all of these natively and quickly; the
  self-host's claim is that it *matches* the interpreter's
  behavior, not its speed.
- The machine's stack is a list, so a program's pending
  work — deeply nested values, long chains of calls not yet
  returned — is bounded by memory as well as by the guards,
  the way any interpreter's stack is bounded by something.
  The guards still speak first for the programs they exist
  for, as the two examples now prove.

## License

Public domain, under the Unlicense — see `LICENSE`. Everything Cardnull
makes is given away the same way.
