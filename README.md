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

Still not built yet, on purpose: the compiler and the Floor.
Those are the next rings.

## License

Public domain, under the Unlicense — see `LICENSE`. Everything Cardnull
makes is given away the same way.
