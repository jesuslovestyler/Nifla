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

## Stone 15 — words on the screen

Laid on **November 14, 2026**, the same evening, fourth of
the six. Bare metal could hold text, measure it, compare
it, and hand it to a floor block — but it couldn't *join*
text, couldn't write a number out as digits, and `say` was
refused: there was no one to say it to. This stone gives
the bare target its voice.

**Joining.** `+` now joins on bare metal, the way it does
everywhere in Nifla: text with text, and text with a whole
number on either side (the number is written out as its
digits first). A text is still an address and a count; a
**joined text is a fresh block from the Stone 13
allocator** holding the two sides side by side, owned by
the program like any block of bytes — which means it is
also never handed back (the allocator does not free), so a
program that joins forever fills the heap and stops, like
a program that makes blocks forever. A number's written
form is built digit by digit into a fresh block of its own,
minus sign and all.

**`say` speaks to the screen.** The bare runtime keeps a
cursor. `say` writes its value — text, or a number by its
digits — at the cursor in the plain color, moves to a fresh
line, wraps at a row's end, honors a newline inside the
text, and **scrolls the screen up** when it fills. The
screen starts cleared, so a saying program begins on a
clean page. (The runtime's writing color is the plain
0x07; placing words in chosen colors is the library's
work, below.)

**The screen library, and preludes.** `barelib/screen.nifla`
is the first bare-metal library, written in Nifla: its work
is floor work, because the screen is the processor's own
memory. It offers `clearscreen()` and
`writeat(row, col, text, color)`, which writes at a chosen
place in a chosen color, stopping at the row's end. A bare
program uses it through the build's smallest honest
library mechanism:

```sh
niflac --bare program.nifla --prelude barelib/screen.nifla -o program.elf
```

A **prelude** is a file of function definitions laid under
the program, as if they stood at its top; a prelude may
only *make* functions — anything else in one is refused in
plain words — and several may be named. To make a library's
shapes knowable, the bare checker now settles them the way
calls declare them: a body whose parameters were pinned by
its calls is checked again with those shapes known, and a
final strict pass over the floor desks refuses any handed
value whose shape is still not known.

**The proof** is `bare-examples/nifla-words.nifla`, run by
`./run-bare-words.sh`: the first rows of the read-back
screen must show a joined greeting ("Hello from Nifla!"),
a join with a computed number ("2 + 3 = 5"), a line built
a join at a time ("1 2 3 4"), a said number ("42"), and —
placed by the library at row 10, column 20 — the word
"Words!" whose **color byte must read 14** (yellow). It
prints PASS — and it does. Scrolling was checked the same
way: thirty said lines leave lines 7 to 30 on the screen,
the cursor resting on the blank last row.

```sh
./run-bare-words.sh   # bare metal: PASS — joined words, said lines, a placed word in its color
```

Honest limits of Stone 15:

- `say` shows **text and whole numbers only**. A true/false
  value or a block of bytes is refused in plain words; join
  a word about it, or say a byte at a time.
- Joined texts are **never freed** (the bump allocator's
  standing limit from Stone 13): each join takes fresh
  memory for good. A long-running program that joins in a
  loop spends memory as it goes and stops when the heap is
  spent.
- Picking one character out of a text (`text[i]`) is still
  not part of bare metal, and neither is comparing a block
  of bytes or joining one; the desk's rules from Stones 9
  and 13 stand.
- `say`'s cursor and the library's placed words are
  independent: `writeat` does not move the cursor, and
  `say` does not know what was placed. A program mixing
  them lays its page out deliberately, or not at all.
- Preludes belong to the **bare build only** for now —
  `niflac` refuses one without `--bare`, in plain words —
  and a prelude's definitions are simply part of the
  program: there is no namespace, so a library function and
  a program function with the same name collide, and the
  checker says so.

## Stone 16 — a disk

Laid on **November 15, 2026**, fifth of the six. Bare metal
could see, hear, remember, and speak — but nothing it made
outlived the power. This stone gives it a disk: whole
sectors, read and written, that are still there when the
machine boots again.

**The controller, chosen plainly.** The first form speaks
**ATA PIO on the primary IDE channel** — ports 0x1F0–0x1F7,
the master drive, 28-bit LBA — because that is the drive
the proof machine (and most simple emulators and old
boards) attaches first, and because programmed I/O needs
no DMA buffers, no bus-mastering setup, and no interrupt
plumbing: the runtime polls the status port until the
drive is ready, then moves 256 words through the data
port. Polling only, honestly: the timer and keyboard
interrupts from Stone 12 keep their own business, and the
disk waits are bounded — a drive that never answers stops
the machine rather than hanging it forever.

**The tools** are bare-only, with plain names:

- `disksectors()` — how many 512-byte sectors the attached
  disk holds, asked of the drive itself (its IDENTIFY
  answer). No drive, or one that won't say: the answer is
  0, not a stopped machine — a program can ask first.
- `diskread(sector, block)` — reads one whole sector into
  a `bytes` block, and gives back 512.
- `diskwrite(sector, block)` — writes one whole sector
  from a `bytes` block, flushes the drive's cache, and
  gives back 512.

The block must hold at least a sector — a smaller one
stops the machine, rather than reading or writing past
its end. A read or write the drive refuses (or no drive
at all) likewise stops the machine: these are raw-sector
tools, and a silent half-write is worse than a halt.
Hosted Nifla refuses the three names the ordinary way —
they are the bare machine's tools, like `ticks()` and
`memorysize()` before them.

**A note on the road here.** The runtime's growth pushed
the multiboot header — which a loader looks for in the
file's first 8192 bytes — past that window in its own
section, and the emulator refused the program whole. The
header now stands as the first bytes of the text section
itself, where it cannot drift; every bare proof re-passed
after the move.

**The proof** is `bare-examples/nifla-disk.nifla`, run by
`./run-bare-disk.sh`. The script makes a scratch disk
image — 8 MiB, a known marker written at sector 4, sector
9 blank — and boots the program twice against it. Boot 1
must show the marker it read ("DISK MARKER SECTOR"), the
disk's size in sectors as the drive reported it
("sectors on this disk: 16384"), and its own verdict
"WROTE - and read it back", after writing a message and a
counting pattern to sector 9 and reading them back. Boot 2
— a fresh machine, the same image — must show the marker
again, the count again, the message itself ("NIFLA WAS
HERE"), and "FOUND - it persisted". It prints PASS — and
it does.

```sh
./run-bare-disk.sh   # bare metal: PASS — sectors read and written on a scratch image, persisting across boots
```

**SAFETY, in plain words:** these tools address **raw
sectors of an attached disk** — no partitions, no
filesystem, no names, no undo. Sector numbers are the
disk's own. The proofs only ever attach the scratch image
the script itself creates; a program (or a person) that
points `diskwrite` at a real disk's early sectors will
destroy whatever lives there. That is what the tool is;
handle it like one.

Honest limits of Stone 16:

- **Primary channel, master drive, ATA PIO, LBA28** —
  one disk, the first one. No second channel, no slave,
  no SATA/AHCI, no NVMe, no DMA, no 48-bit LBA: disks
  past 128 GiB report their LBA28 size and only their
  first stretch is addressable.
- **Whole 512-byte sectors only.** Read or write a part
  of a sector by moving the whole sector through a block
  and changing the bytes you mean to change — as the
  proof does.
- **Polling, with bounded waits.** A healthy drive
  answers at once; a dead or missing one stops the
  machine on read/write (and answers 0 to
  `disksectors()`), never corrupts quietly.
- No partitions and no filesystem: the program owns the
  meaning of every sector number itself. The guest door
  (Stone 17) is the first tenant of that arrangement.

**An opt-in asked of the loader (added November 15, 2026,
at Cardnull OS 2's Stone 9).** A bare build may now carry
`--video WIDTHxHEIGHTxDEPTH` (like `--video 1024x768x32`):
the multiboot header then sets its video flag (bit 2) and
asks the loader for a linear graphics mode of that shape —
mode_type 0 and the width, height, and depth standing in
their own places in the header (offsets 32, 36, 40, 44),
the header's unused address words zero between the
checksum and the mode. The loader's answer, when it gives
one, stands in the boot information's framebuffer fields
(flags bit 12; address at 88, pitch at 96, width at 100,
height at 104, bits per pixel at 108, type at 109, and the
color fields' places at 112–117), for the program to read
and decide on. The request is strictly opt-in: without
`--video`, the header is emitted exactly as it always was
— verified byte-for-byte against the previous build — and
every existing bare proof stands unchanged. A loader that
cannot give the mode still boots the program, with the
framebuffer fields silent. `--video` without `--bare`, or
on a guest (which no loader ever boots), is refused in
plain words.

## Stone 17 — guests

Laid on **November 15, 2026**, last of the six. Bare metal
had a machine that could see, hear, remember, speak, and
keep things on a disk. This stone opens its door: a host
program loads a second program — a **guest** — checks it
is whole, calls it, and takes it back when it returns.
The first form of the guest door; the .feather's manners,
arriving early.

**Building a guest.** A guest is an ordinary bare Nifla
program built one flag further:

```sh
niflac --bare --guest guest.nifla -o guest.bin
```

The build packages the flat bytes of the image (text,
then the read-only words, then data) and links it for
**the doorstep: the half megabyte at 2097152 (2 MiB)**,
the address every guest stands at. A guest does not
boot: no multiboot header, no stub of its own — the host
is already running the machine.

**The door.** A host receives a guest like this, all of
it plain Nifla and floor work:

1. Read the guest's **card** from the disk — a sector
   saying where the image starts, how long it is, and
   what its checksum must be. (The proof's card is laid
   by the proof script; a real host would keep its own.)
2. Load the image into a block and reckon its **FNV-1a
   checksum** (the 64-bit form: the offset basis, then
   each byte xored in and multiplied by the FNV prime).
   If the reckoning and the card disagree, the guest is
   **refused** — the host says so on screen and never
   runs it. A changed byte anywhere in the image changes
   the sum; that is the whole of the check, and the
   proof's second boot flips one byte to watch the
   refusal happen.
3. Lay the image at the doorstep (a floor block wipes
   the region clean first, so the guest's scratch memory
   starts at zero as a booted program's does, then
   copies the image in).
4. Call it: `callguest(2097152, gift)` — the address,
   and one whole number for the guest.

**The desk.** The call hands the guest a small card in
memory — the desk — and the guest's world is defined by
it:

- the **screen**, shared: the desk carries the host's
  cursor row and column in, and the guest's cursor back
  out, so a guest's `say` continues the host's page and
  the host's next `say` continues the guest's;
- a **heap of its own**: from its image's end to the
  guest region's end — `makebytes`, joins, and the rest
  of the allocator's work draw on it;
- one **number from the host**, read with `guestvalue()`;
- and a way back: `guestgive(n)` leaves a parting
  number, which becomes the value of the host's
  `callguest` call. When the guest's program ends, it
  **returns** — it does not stop the machine — and the
  host goes on.

A guest does **not** own the machine: the timer, the
keyboard, the memory map, and the disk stay with the
host, and a guest program that asks for `ticks()`,
`readkey()`, `memorysize()`, or the disk tools is
refused in plain words before it is built — as is a
host program that reaches for `guestvalue()`, and a
guest that tries to call a guest. The door has two
sides, and the checker keeps each side's tools on it.

**The proof** is `bare-examples/nifla-host.nifla` and
`bare-examples/nifla-guest.nifla`, run by
`./run-bare-guest.sh`. The script builds both, lays the
guest on a scratch image with its card, and boots the
host twice. Boot 1's screen must read, in order:
"HOST: before the guest", "GUEST: I am running",
"GUEST: the host sent 7", "GUEST: twice the gift is 14",
"HOST: back again - the guest gave 42" — one shared
page, in order, the parting number come home. Boot 2
flips one byte of the guest on the image: the host must
answer "HOST: the guest on disk is not whole - I will
not run it", and no guest line may appear. It prints
PASS — and it does.

```sh
./run-bare-guest.sh   # bare metal: PASS — a guest loaded, checksum-verified, called, and returned from; a tampered guest refused
```

Honest limits of Stone 17 — read these plainly:

- **There is NO isolation or protection.** Host and
  guest share one privilege level, one memory, one
  machine. A guest can read or write anything the host
  can — the screen, the disk (through raw floor work),
  the host's own memory. The checksum proves the bytes
  are the bytes that were laid on the disk; it does not
  make them trustworthy, and it is not a signature —
  anyone who can write the disk can write a matching
  card. This is the guest door's **first form**: not
  the feather format, and **not a security boundary**.
- A guest that **faults** — a guard tripped, a bad
  floor block — stops the whole machine, host and all.
  There is no catching a guest's fall yet.
- **One guest shape only**: linked for the doorstep at
  2 MiB, in a region of half a megabyte, image and heap
  together. A bigger guest does not fit; a host must
  keep its own heap below the doorstep while it means
  to receive guests (the allocator does not yet enforce
  the reservation — the proof host uses well under half
  the room), and one guest at a time is called, on the
  host's own stack.
- The guest's heap is **fresh each call** (the region
  is wiped as it is laid), and nothing a guest makes
  outlives its return except what it wrote to the
  screen, the disk, or the desk's parting number.

A later verification, recorded here because it belongs
to this stone's subject (made at Cardnull OS 2's
Stone 10, November 15, 2026): a guest's floor blocks
**can be handed a piece of text or a block of bytes, and
receive them whole** — pointer, length, and letters —
in every shape: a literal or a block handed in the main
body, a function's own handed words passed onward to
its floor, joined and returned text, text handed with
numbers. An early bench record elsewhere claimed the
handed desk read as zero; measured again shape by
shape, it did not hold, and the assembly the compiler
writes for the handing is the same for a guest as for a
host (apart from the position-independent spelling of
addresses, which is the guest build's design). No
compiler change was needed. The standing proof is
`run-bare-guest-desk.sh` over
`bare-examples/nifla-guest-desk.nifla`: the guest hands
back one reckoned number over all the shapes
(56895 = 5·10000 + 64·100 + 495) and paints the line it
was handed, on the host's screen.

```sh
./run-bare-guest-desk.sh   # bare metal: PASS — a guest's floor blocks handed text and bytes receive them whole
```

## Stone 18 — marks of kind, and a checker that proves more

Tyler asked how Nifla could become better than Swift. The
answer this stone builds: keep the JavaScript-readable
dynamic surface — no program that ran before needs a single
new word — and grow the checker so it proves more before
anything runs, with **optional kind annotations** for the
places a writer wants a promise kept. Annotations are
offered, never required.

### The marks

A variable can be marked with the kind it must hold:

```
let name: text = "Tyler"
let count: number = 3
```

A function's values can be marked, and a function can
promise the kind it gives back, after an arrow:

```
make greet(who: text, times: number) -> text {
    give who + " x" + times
}
make quiet() -> nothing {
    say "inside"
}
```

The kind words are the checker's own vocabulary — no
parallel set was invented: **number, text, boolean, list,
object, bytes, nothing**. (`boolean` is spoken of as "a
true/false value" in messages, as the checker always has.)

Where an annotation exists, two keepers watch it:

1. **The checker**, before anything runs, refuses any
   assignment, call, or `give` whose kind it can *prove*
   breaks the mark — in plain words, with the line number
   and the checker's signature: "I caught this before the
   program ran, so nothing ran."
2. **A runtime guard** at the annotated boundary — the
   `let` line, every later setting of the variable, each
   annotated parameter at a call, each `give` in a
   return-marked function, and the end of such a function
   reached without a `give` — checks the actual value
   where the checker couldn't prove either way, and stops
   with the same plain words. An annotated boundary never
   silently receives the wrong kind.

All four mirrors keep the marks: the Swift interpreter
(parses them, guards at runtime), the compiled runtime
(the same guards, the same words), the checker, and the
self-host (its parser accepts them and its evaluator
enforces the runtime guards with the same messages — the
self-host has no checker of its own, as it never has).
Bare metal accepts annotations in the shapes it holds —
number, text, true/false, bytes — checked by the checker
and the BareValidator together; a mark naming a kind bare
metal can't hold (a list, an object, nothing) is refused
in plain words, annotation or not, exactly as the value
itself would be. Proofs: `examples/annotated.nifla` (the
marks, kept), `examples/kindguard.nifla`,
`examples/paramguard.nifla`, `examples/giveguard.nifla`,
`examples/nogive.nifla` (the runtime guards),
`checker-examples/annotatedlet/annotatedparam/
annotatedgive.nifla` (the checker's refusals), and
`run-bare-kinds.sh` (bare metal: an annotated program
boots and runs; three annotated mistakes are refused).

### The checker proves more

The checker now tracks three simple facts alongside kinds
— a variable's constant number, a list variable's
emptiness, and a list or text variable's exact length —
each held only while it is provable, and given up the
moment anything could change it quietly (a call, a list
tool, a handing-on of the list to another name, a road
through an `if` that disagrees). Facts never cross into a
function body from outside: another function could change
the variable before the call, so inside a body only facts
the body itself establishes are provable. From those
facts, before anything runs, the checker now refuses:

- a `repeat` count it can prove is negative — on the
  hosted side too (it was the run's discovery before);
- `exitwith` with a provably non-whole number, or one
  outside 0–255;
- `makebytes` with a provably negative count or one over
  the 16,777,216 cap;
- an index provably outside a list or text whose length
  is known — a literal's, or a variable's tracked from
  its making — including any index into a provably empty
  list, and any negative index into a known list, text,
  or block of bytes;
- `removeat` on a provably empty list, or past the end of
  a list of known length;
- a `part` span provably outside a literal text (a
  negative start or count, a start past the end, a span
  running past the end);
- division by a provably zero divisor. (Nifla has no
  modulo sign — `/` is the only divisor there is, so
  there is no modulo case to refuse.)

Each refusal speaks in the run's own words, plus the
checker's signature. Proofs: the new `checker-examples/`
(`repeatneg`, `divzero`, `exitrange`, `exitfrac`,
`bytesneg`, `bytesbig`, `textindex`, `emptyindex`,
`emptyremove`, `removeoob`, `partstart`, `partspan`,
`negindex`), and two older examples moved house because
this stone made their mistakes provable before the run:
`badrepeat` and `badindex` now live in `checker-examples/`
with the checker's wording. One more honest consequence:
`examples/attempt.nifla` now makes its zero at runtime
(`length("")`), because a zero written plainly — `10 / 0`
— is refused before the program starts; a runtime zero is
still `attempt`'s to catch, and the example still teaches
exactly that.

Floor blocks gain from the marks for free: an annotated
variable's kind is known to the checker even inside an
unannotated function, so the desk rules that already
refused a true/false value handed to the floor now refuse
it on the annotation's proof too
(`checker-examples/floorannot.nifla`). Every existing
floor refusal stands unchanged.

### The gap ledger

Tyler's instruction was "fix all safety gaps." The honest
deliverable is every closable gap closed, and every
remaining one named with its reason.

**Closed by this stone:**

- Annotated boundaries could silently receive a wrong
  kind wherever the checker couldn't prove the value
  (anything arriving through unannotated code). Now a
  runtime guard stands at every annotated boundary, in
  every mirror.
- The provable range mistakes listed above were learned
  only when the run reached them — a negative `repeat`
  count, an oversized `makebytes`, a parting number
  outside 0–255, indexes and `part` spans outside known
  lengths, division by a written-out zero. The checker
  now proves and refuses them before anything runs,
  hosted and bare alike.
- A floor block's desk inputs arriving from annotated
  variables were unprovable; the annotation is now proof
  the existing desk rules can bite on.

**Remaining, named:**

- **Fully dynamic, unannotated code keeps today's runtime
  checks.** Where nothing is written and nothing can be
  proven — a value from a call, a field, an item, input —
  the checker stays silent *by design*: silence is not a
  promise, and the runtime's own checks (which stop the
  program in plain words) remain the keeper there. This
  is the JavaScript-readable surface Tyler chose to keep;
  annotations are how a writer asks for more.
- **Raw floor assembly is unchecked — deliberately, not
  as a gap.** The floor is raw processor talk: the words
  inside a floor block are the processor's, and no
  checker reads them. What is checked is the desk around
  it — the kinds of the values handed in and out. A floor
  block can still halt the machine, and on bare metal it
  can still reach any memory. That is what the floor is
  *for*; it is a boundary, named here so no one mistakes
  it for an oversight.
- **Proofs reach only as far as literals and simple
  tracked facts.** Anything computed — through a call, a
  field, an item, arithmetic the checker doesn't fold —
  is unprovable, and deliberately left to the runtime
  rather than guessed at. A checker that guesses would
  refuse good programs; this one would rather stay
  silent and let the run speak.
- **Tracked facts are conservative around sharing.**
  Lists are shared by reference, so when a proven list is
  handed to another name, the facts about it are given
  up — the other name could grow it where the checker
  can't watch. Some provable things are therefore not
  proven; the checker errs toward silence.
- **The self-host has no checker.** It never has: it
  parses and runs, and its refusals are the runtime's.
  The checker's pre-run refusals (this stone's included)
  are proven by the Swift tools' suites
  (`checker-examples/`); the self-host proves the marks
  it can — parsing them, and the runtime guards — in the
  shared `examples/` suite.
- **Bare metal's guards are the machine's halt, as
  before.** The bare subset has no runtime error channel:
  an unprovable index or count there stops the machine
  (Stone 13's design). Annotations narrow what can be
  *built*; they do not give bare metal a voice it doesn't
  have.

The guards' numbers are unchanged: a million loop passes,
five hundred calls deep, 16,777,216 bytes to a block.

## Stone 19 — checked absence: `maybe` and `nothing`

Stone 18 gave values marks of kind. This stone gives the
language the kind of value every real program meets sooner
or later: **absence** — and makes it a checked thing, in
the same spirit. A value that may not be there is marked
`maybe`; the empty value itself is written `nothing`; and
using a maybe where the nothing road is unhandled is
refused — before the run, wherever the checker can prove
it, and at the boundary everywhere else.

### The words

`nothing` is a value now, the way `true` and `false` are:

```
say nothing            // prints: nothing
nothing == nothing     // true — that is how a maybe is checked
nothing == 5           // false
```

A `maybe` mark stands before any kind but `nothing`
(`maybe nothing` is refused at the reading — it says no
more than `nothing` itself):

```
make lookup(name) -> maybe number {
    if name == "Tyler" {
        give 29
    }
}

let a: maybe number = lookup("Tyler")
let b: maybe number = lookup("Noki")
```

A function marked `maybe` that finishes without a `give`
hands back the empty value — that is exactly what the mark
says may happen. A function marked `-> nothing` still
hands nothing back at all: a `give nothing` line inside it
is an early way out, and the empty value it names is
absorbed by the promise.

### Handling both roads

The unwrapping shape is the language's own `if`, and it
*forces* nothing new to be learned — a maybe is handled by
checking it against `nothing`, and the checker **narrows**
the variable on each road:

```
if b == nothing {
    say "b is missing"
} else {
    say b + 1          // here the checker knows b is a number
}
```

Inside the `== nothing` road the variable is known to be
the empty value; in the `else` it is known to be the kind
itself. `!=` narrows the other way around. A `while` body
sees the road where its test held, and what follows the
loop sees the road where it failed — the only way out —
so the fill-in loop reads plainly:

```
let c: maybe number = nothing
while c == nothing {
    c = 7
}
say c * 2              // the checker knows c is a number here
```

Narrowing is earned only by that plain test — a variable
tested against `nothing` (or against a variable proven to
hold it). Anything cleverer stays unproven, and the
runtime guard speaks instead, as everywhere in Nifla.

### What is refused, and where

**The checker refuses, before anything runs**, a proven
maybe — or a proven `nothing` — used where a value that is
surely there is needed:

- in `+ - * /` or a size comparison (`< <= > >=`) —
  except `+` with text on either side, which joins
  anything, the empty value by its name, as the run does;
- under a minus sign, as an item-picker, as the value
  picked from, or as the object a field is read from;
- as a `repeat` count, or as what a `for` walks;
- handed to a built-in tool that needs a definite kind
  (the refusal names the check to make first);
- handed to a parameter, a `give`, a `let`, or a setting
  whose mark is a plain kind — the Stone 18 boundary
  refusals, with the maybe now one of the kinds that can
  break them.

**The runtime guards catch the rest**, in all four
mirrors, in the same plain words: an operation that meets
the empty value stops and says why, and names the check
("Nothing is the empty value: there is nothing there to
work with. If a value might be nothing, check it first —
if value == nothing { ... } else { ... } — and use it in
the 'else', where it is known to be there."). The Stone 18
annotation guards speak for `maybe` marks unchanged: a
maybe boundary accepts the kind it names or the empty
value, and nothing else.

Nothing else about values changed. `nothing` can be held
in a list or an object, said, joined onto text (by its
name), and compared with `==` and `!=`. Tools that need a
definite kind refuse it at the run, as they refuse any
wrong kind.

### Bare metal stands apart — plainly

Absence is **not** part of the bare subset, and the
refusal says why: a bare value is a machine word with one
pinned shape, and the empty value has no word to be;
there is no runtime there to hold the difference. A bare
build that uses `nothing`, or marks a `maybe`, is refused
before building, in plain words (`run-bare-kinds.sh`
proves both refusals, beside the Stone 18 ones). This is
recorded as a standing-apart, not a gap to close later
without thought: a bare maybe would need a second word
everywhere a value travels, which is a different machine
contract, to be taken up as its own stone if ever.

### Proofs

- `examples/maybe.nifla` — the happy road in full: the
  empty value said and compared, a `-> maybe number`
  finder found and missing, both narrowings, the
  fill-in loop, joining with nothing — run by the
  interpreted, compiled, and self-hosted suites alike.
- `examples/nothingguard.nifla` — the runtime guard: the
  empty value carried through an unannotated function
  (where the checker honestly can't prove it) meets `+`,
  and every mirror refuses it in the same words.
- `checker-examples/maybearith.nifla`,
  `maybegive.nifla`, `maybeparam.nifla`,
  `maybeset.nifla`, `nothingarith.nifla` — the checker's
  refusals: a maybe in arithmetic, the empty value given
  against a plain promise, a maybe handed to a plain
  parameter, a maybe set into a plain mark, and proven
  `nothing` itself in arithmetic.
- `run-bare-kinds.sh` parts 5 and 6 — bare metal refuses
  `nothing` and the `maybe` mark, in plain words.

### The gap ledger, updated

**Closed by this stone:**

- Absence itself was the remaining unmarked kind of
  value: a function that found nothing had to hand back
  a lie (a 0, an empty text) or stop the program. A
  `maybe` mark now says the truth, and the checker and
  the guards keep it — a maybe cannot flow silently into
  a place that needs a value surely there.

**Remaining, named:**

- **Narrowing is earned only by the plain test** — a
  variable compared with `nothing` (or with a variable
  proven to hold it). A maybe learned from a tool, a
  field, or a compound condition is not narrowed; the
  runtime guard is the keeper there. Widening what the
  checker can prove is future work, taken up only where
  the proof stays honest.
- **Bare metal has no absence** — recorded above as a
  standing-apart with its reason, not an oversight.

## Stone 20 — feathers from the compiler (November 15, 2026)

A guest program has always traveled with a card in spirit:
a host's door wants to know a program's name, what it
needs, and whether its bytes are whole, before it runs
anything. Until this stone the card was somebody else's
job — Cardnull OS 2's build laid a separate binary card
beside its welcome feather with a Python tool. Now the
compiler lays the card itself:

```
niflac --bare --guest --feather program.nifla -o program.feather
```

`--feather` without `--guest` is refused in plain words:
a feather is a guest program together with its card. The
`.feather` file is the plain guest build, byte for byte,
with a plain-text card standing at its head — the OS 1
format's shape, a card and not a signature:

```
CARDNULL FEATHER 1
name: welcome-feather
needs: the guest door (desk version 1)
bytes: 2656
checksum: 0b2452a707571de8

<the program bytes>
```

The name is the program file's own name; the needs line
names the guest door (desk version 1) every guest is built
for today; the byte count and the FNV-1a-64 checksum (the
same reckoning the language's Stone 17 card check uses)
are over the program bytes alone — everything after the
card's blank line. A door reads the card, reckons the
checksum over the program, and runs it only when the two
agree. The checksum proves the bytes match the card and
nothing more; it is not a signature, and the door's
standing honesty (no isolation yet) is unchanged.

Standing proof: `run-feather.sh` — it builds a guest both
ways and checks the card line by line (name, needs, byte
count against the program part, checksum against a fresh
independent reckoning), checks the program part is the
plain guest build byte for byte, and checks the
`--feather`-without-`--guest` refusal and that it leaves
no file behind.

**Adoption — Cardnull OS 2 took the mode the same day.**
Its build now produces `build/welcome.feather` with
`--feather`, and its disc carries two modules where three
rode before: the settings, and the feather as ONE file
(`feather.fea` on the disc), its card at its head. The
OS's door (its `featherdoor.nifla`) reads the card from
the feather itself — the card's lines parsed in plain
Nifla, the checksum reckoned over the program bytes after
the card's blank line, a tampered feather still refused
in the same plain words ("The feather on this disc is not
whole, so it was not let in."). Both of the OS's own
loaders (BIOS and EFI) lay two module entries now. The
OS's `tools/make-modules.py` shrank to the one thing that
is still honestly its own — the settings module; the card
half retired, and the tool says so in its header. The
OS's full proof regression (all fifteen proofs) passes on
the adopted build, including its Stone 5 door proof: the
feather as laid visits, and a copy with one program byte
flipped is refused and never appears. The language's own
words for the guest machinery (`callguest`, `guestvalue`,
`guestgive`, `--guest`) are plumbing and did not change;
feather is the format's name, not a renaming.

## Stone 21 — the feather checker (November 15, 2026)

A door checks a feather before letting it in; this stone
gives that same check to anyone, as a small standalone
tool. The repo's one program gains a third name (the
build decides by the name it is called by, as with
`nifla` and `niflac`):

```
feathercheck program.feather
```

It reads the `.feather`, reads its card as the compiler
lays it — first line, `name:`, `needs:`, `bytes:`,
`checksum:`, blank line, then the program — reckons the
FNV-1a-64 checksum over the program bytes as they stand,
and answers in plain words:

```
Feather: welcome-feather
Needs: the guest door (desk version 1)
The card says the program is 2656 bytes, with checksum 0b2452a707571de8.
The program as it stands is 2656 bytes, with checksum 0b2452a707571de8.
The card is true: the program is whole, and a door may let this feather in.
```

The exit code carries the verdict too: 0 when the card is
true, 1 when it is not, 2 when the tool was called
wrongly. A program whose bytes were tampered with gets
the not-true verdict ("The card is not true: the program
does not match its card, so a door must refuse this
feather."); a damaged card — a wrong first line, a
missing line, a checksum that is not sixteen hex letters,
a card whose blank line never comes — is refused as not
a whole feather, with the damage named in plain words.
(The OS's door needs only the `bytes:` and `checksum:`
lines to do its work and steps over the rest; the
checker reads the whole card, as it was laid.)

Standing proof: `run-feathercheck.sh` — a true feather
passes with stated and reckoned checksums agreeing; one
byte flipped in the program is declared not true; a
checksum letter struck from the card is refused as
damage. This is the doorman's test anyone can run.

## Stone 22 — the Nifla Primer (November 15, 2026)

The language has a book now: `PRIMER.md`, in this
repository. It walks through every grammar word and every
toolbox word — saying and keeping, numbers and text,
deciding and repeating, lists and objects, functions,
`attempt`, the toolbox tool by tool, kind marks and
checked absence, the floor and its desk, and the bare
subset with its own tools, guests, and feathers — each
with a short plain explanation and a small runnable
example, written for a reader who reads Nifla like
JavaScript and learns by seeing code.

The book cannot drift from the language: a standing proof,
`run-primer.sh`, extracts every example from the Primer
and runs it — interpreted, and compiled where the example
can be compiled (floor examples compiled only, since the
interpreter refuses floor code by design; bare examples
compiled with `--bare`, and `--bare --guest` for the
guest's side) — and compares the output, line for line,
with the output the book prints. The proof joins the
repo's test flow beside the other `run-*.sh` scripts; if
an example ever stops being true, the proof fails. (Its
first run earned its keep: it caught the book saying text
inside a list speaks bare — it speaks with its quotes on —
and `sayerr` written as a statement where it is a tool
call. The book now says both rightly, and the proof holds
it to them.)

## License

Public domain, under the Unlicense — see `LICENSE`. Everything Cardnull
makes is given away the same way.
