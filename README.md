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

## License

Public domain, under the Unlicense — see `LICENSE`. Everything Cardnull
makes is given away the same way.
