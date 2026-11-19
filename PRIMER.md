# The Nifla Primer

Nifla is a small programming language that speaks in plain
words. It was made to be read: if you can read a little
JavaScript, you can read Nifla, and most of what surprises
people is how little there is to memorize. This book walks
through every word of the language, one at a time, each
with a small program you can run.

Three programs carry the language:

- `nifla program.nifla` — checks a program, then runs it.
- `niflac program.nifla` — checks it, then compiles it into
  a program that stands on its own. With `--bare` it
  compiles a smaller, sterner subset of the language into a
  binary that boots on bare metal, with no operating system
  underneath; with `--bare --guest --feather` it makes a
  *feather* — a guest program with its card laid on it, the
  form a host's door receives (see the last part of this
  book).
- `feathercheck program.feather` — reads a feather and
  answers, in plain words, whether its card is true.

Every example in this book is real. A standing proof
(`run-primer.sh`) takes each one out of the book and runs
it — interpreted, and compiled where it can be — and the
proof fails if any example's output drifts from what the
book says. What you read here is what the language does.

A word about errors, before we start: when a Nifla program
goes wrong, the language answers in plain words, with the
line number, and tries to say what would fix it. And before
a program runs at all, a *checker* reads it and refuses —
in the same plain words — programs it can prove will go
wrong in certain ways: a misspelled name, a tool handed the
wrong kind of value, a value that might be `nothing` used
as if it were surely there. You will meet the checker as
you go.

---

## Part 1 — Saying, keeping, and deciding

### `say` — speaking a value

`say` prints a value and a new line. It is the way a
program talks to the person running it.

```nifla
say "Shalom"
say 42
say true
```

```expected
Shalom
42
true
```

Every value has a *spoken form* — the words `say` uses for
it. You will see them as the values arrive: a list speaks
as `[1, 2, 3]`, an object as `{ name: "Tyler" }`, and
`nothing` speaks as `nothing`. One refinement: inside a
list or an object, text keeps its quotes on, as the object
there shows — so a list of words can never be mistaken for
anything else. Said on its own, text speaks bare.

Lines that begin with `//` are comments — notes to the
reader that the language steps over.

### `let` — keeping a value under a name

`let` gives a value a name. After that, the name can be
used anywhere the value could, and the name can be given a
new value with a plain `=`.

```nifla
let name = "Tyler"
let years = 29
say name
say years
years = years + 1
say years
```

```expected
Tyler
29
30
```

Names are how programs remember. A name made inside a
pair of braces `{ }` belongs to that stretch of the
program and is not seen outside it; a name made by `make`
(a function, below) belongs to the whole program.

### Numbers

Numbers are the language's counting and measuring values.
Whole numbers are exact up to 2⁵³; fractions are held as
precisely as the machine's own fractions. The arithmetic
words are `+`, `-`, `*`, and `/`, with parentheses to say
what goes first, and a `-` in front of a number to negate
it.

```nifla
say 1 + 2 * 3
say (1 + 2) * 3
say 7 / 2
say 6 / 2
say 0 - 5
```

```expected
7
9
3.5
3
-5
```

Division by zero is refused in plain words — before the
program runs when the zero is written plainly, and as a
catchable problem (see `attempt`, below) when it arises
along the way.

### Text

Text is words between double quotes. Joining text with `+`
speaks the other side into the text, whatever it is —
that is how a program builds a sentence out of pieces.

```nifla
let psalm = "Psalm "
say psalm + 127
say "Tyler" + " builds"
say "The answer is " + (6 * 7) + "."
```

```expected
Psalm 127
Tyler builds
The answer is 42.
```

Text can also be added to a number the other way around
only through its spoken form: `"Psalm " + 127` works
because the left side is text. Number `+` text is refused —
add a piece of text first, as above.

### `true`, `false`, and comparisons

A comparison asks a question and answers `true` or
`false`: `==` (is it the same), `!=` (is it different),
`<`, `<=`, `>`, `>=`.

```nifla
say 3 == 3
say 3 != 3
say 2 < 5
say "apple" == "apple"
say [1, 2] == [1, 2]
```

```expected
true
false
true
true
false
```

Two things to notice. Values of different kinds are never
equal — the number 3 is not the text "3". And lists and
objects compare by *identity*, not by contents: two lists
that merely look alike are not the same list. (The last
line above says `false` for exactly that reason; a list
compared with *itself* — the same list under another name —
says `true`.)

There are no `and` / `or` / `not` words. Questions are
combined by asking them one at a time, with nested `if`s
— a little plainer, and nothing hides.

### `if` and `else` — deciding

`if` runs a stretch of code when its question answers
true, and `else` — when there is one — runs the other
stretch when it answers false. The question must be a
true/false value; the language refuses anything else in
plain words.

```nifla
let years = 29
if years >= 18 {
    say "Grown"
} else {
    say "Young"
}
if years == 29 {
    say "Twenty-nine, exactly"
}
```

```expected
Grown
Twenty-nine, exactly
```

### `while` — again, while a question holds

`while` repeats its stretch as long as its question keeps
answering true.

```nifla
let n = 1
while n <= 3 {
    say n
    n = n + 1
}
say "Done"
```

```expected
1
2
3
Done
```

A guard stands over every loop: one loop that passes a
million times without finishing is stopped and told so,
in plain words — a runaway program helps no one. The
count belongs to the one loop's run (Stone 33): each
loop that starts is given a fresh million of its own, so
a program of many loops, each finishing, may pass a
million times in all and run on — a program that runs
forever by design, like an operating system's main loop
of finishing loops, is not a runaway.

### `repeat` — again, a counted number of times

`repeat` runs its stretch a whole number of times.

```nifla
repeat 3 {
    say "Again"
}
```

```expected
Again
Again
Again
```

### Lists — a row of values

A list is written between `[ ]`, its values separated by
commas. Items are numbered from 0, and `list[i]` reaches
one item. A list can hold any values, mixed as you please,
and lists are shared: two names for one list are two names
for the *same* list, so a change seen through one name is
seen through the other.

```nifla
let colors = ["red", "green", "blue"]
say colors[0]
say colors[2]
colors[1] = "gold"
say colors
say length(colors)
```

```expected
red
blue
["red", "gold", "blue"]
3
```

Reaching past the end of a list is refused in plain words
that say how many items there are. (`length` is a toolbox
word — Part 2.)

### `for … in` — walking a list

`for` takes each item of a list in turn, under a name,
and runs its stretch once per item.

```nifla
let names = ["Ada", "Byron", "Caleb"]
for name in names {
    say "Hello, " + name
}
```

```expected
Hello, Ada
Hello, Byron
Hello, Caleb
```

### Objects — values with named fields

An object is written between `{ }`, each field a name, a
colon, and a value. `person.name` reaches a field, and a
field can be given — or given for the first time — with
the same dot.

```nifla
let person = { name: "Tyler", town: "Home" }
say person.name
person.town = "Sicily one day"
person.years = 29
say person
```

```expected
Tyler
{ name: "Tyler", town: "Sicily one day", years: 29 }
```

Fields keep the order they were first given, as the spoken
form shows. Asking for a field an object does not have is
refused in plain words.

### `make` and `give` — functions

`make` builds a function: a named stretch of code that can
be handed values (its *parameters*, in parentheses) and
can hand one value back with `give`.

```nifla
make greet(name) {
    give "Hello, " + name
}
make twice(n) {
    give n * 2
}
say greet("Noki")
say twice(21)
```

```expected
Hello, Noki
42
```

A function that reaches its end without `give` hands back
nothing at all — which matters once `maybe` arrives, in
Part 3. Functions can call themselves (that is how some
counting is done), with a guard: calls nested deeper than
500 are stopped in plain words.

### `attempt` and `if it fails` — catching a problem

Some problems only arise along the way: a file that is not
there, a division by a number that turned out to be zero.
`attempt` runs a stretch, and if a problem arises inside
it, the `if it fails` stretch runs instead, with the
problem's own words waiting in the name `problem`.

```nifla
attempt {
    let notes = readfile("notes-that-are-not-there.txt")
    say notes
} if it fails {
    say "No notes yet — starting fresh."
}
say "The program carries on"
```

```expected
No notes yet — starting fresh.
The program carries on
```

And a problem whose words you want to hear goes through
`problem`:

```nifla
attempt {
    let zero = length("")
    say 10 / zero
} if it fails {
    say "That sum went wrong: " + problem
}
```

```expected
That sum went wrong: I can't divide by zero. Dividing needs a second number that isn't zero.
```

Notice the zero in that example is *worked out while the
program runs* (`length("")` is 0). A zero written plainly —
`10 / 0` — never reaches `attempt` at all: the checker
proves it before the program starts and refuses the whole
program in plain words. That is the two of them working
together — the checker catches what can be proven ahead of
time, and `attempt` catches the rest, as it happens.


---

## Part 2 — The toolbox

The toolbox is the set of tools a program calls by name,
like functions that were always there. Each one is handed
values in parentheses and hands one value back. Hand a tool
the wrong kind of value and it refuses in plain words,
naming the tool and showing how it is called.

### `length` — how much of something there is

For text, the number of characters; for a list, the number
of items; for a block of bytes, the number of bytes.

```nifla
say length("Tyler")
say length([10, 20, 30])
say length("")
```

```expected
5
3
0
```

### `part` — a piece of some text

`part(text, start, count)` takes `count` characters of
text starting at character `start` — the first character
is number 0.

```nifla
say part("Tyler", 0, 2)
say part("Tyler", 3, 2)
```

```expected
Ty
er
```

### `find` — where a piece of text sits

`find(text, piece)` gives the character number where the
piece first appears, or -1 when it is not there at all.

```nifla
say find("Tyler", "y")
say find("Tyler", "z")
```

```expected
1
-1
```

### `split` — text into a list

`split(text, separator)` cuts text at every separator and
gives back the pieces, as a list.

```nifla
say split("a,b,c", ",")
say split("one two", " ")
```

```expected
["a", "b", "c"]
["one", "two"]
```

### `join` — a list into text

`join(list, separator)` speaks every item of a list and
joins the spoken forms with the separator between them —
`split`'s way back.

```nifla
say join(["red", "gold", "blue"], ", ")
say join([1, 2, 3], " + ")
```

```expected
red, gold, blue
1 + 2 + 3
```

### `append` — one more item on the end

`append(list, value)` adds a value to the end of a list.
Lists are shared, so the list itself grows; the tool also
hands the list back, for chaining or saying.

```nifla
let items = [1, 2]
append(items, 3)
say items
```

```expected
[1, 2, 3]
```

### `insertat` — an item into the middle

`insertat(list, index, value)` puts a value into a list at
the numbered place, moving the later items one step along.
The index may be the list's length, which puts it at the
end, like `append`.

```nifla
let items = ["a", "c"]
insertat(items, 1, "b")
say items
```

```expected
["a", "b", "c"]
```

### `removeat` — an item out of a list

`removeat(list, index)` takes the numbered item out of a
list and hands *the removed item* back.

```nifla
let items = ["a", "b", "c"]
let taken = removeat(items, 1)
say taken
say items
```

```expected
b
["a", "c"]
```

### `sorted` — a list in order

`sorted(list)` hands back a *new* list with the items in
order — numbers in number order, text in letter order. The
list it was given is left as it was.

```nifla
say sorted([3, 1, 2])
say sorted(["pear", "apple", "fig"])
```

```expected
[1, 2, 3]
["apple", "fig", "pear"]
```

### `fieldnames` — an object's field names

`fieldnames(object)` gives the object's field names as a
list of text, in the order the fields stand.

```nifla
let person = { name: "Tyler", town: "Home" }
say fieldnames(person)
```

```expected
["name", "town"]
```

### `removefield` — a field out of an object

`removefield(object, name)` takes a field out of an object
and hands *the removed value* back.

```nifla
let person = { name: "Tyler", town: "Home" }
let gone = removefield(person, "town")
say gone
say person
```

```expected
Home
{ name: "Tyler" }
```

### `makebytes` — a block of bytes

`makebytes(count)` makes a block of bytes, every byte 0 to
begin with. Bytes are the language's way of holding raw
data — a picture's pixels, a file's exact contents, a
message for a machine. A byte is reached by number, like a
list item, and holds a whole number from 0 to 255. A block
can hold at most 16 MiB, and blocks are shared, like lists.

```nifla
let data = makebytes(3)
data[0] = 72
data[1] = 105
say data[0] + data[1]
say length(data)
say data
```

```expected
177
3
bytes(72, 105, 0)
```

A byte's spoken form names its numbers, as the last line
shows. Bytes matter most at the floor and on bare metal,
later in this book.

### `readfile` and `writefile` — the program's papers

`writefile(path, text)` writes text to a file, replacing
what was there, and hands back nothing of interest.
`readfile(path)` gives back a file's whole text. A file
that is not there is a problem — `attempt`'s prey, as you
saw in Part 1.

```nifla
writefile("note.txt", "Shalom")
let back = readfile("note.txt")
say back
say length(back)
```

```expected
Shalom
6
```

`readbytes(path)` (Stone 25) reads a file the other way:
not as text, but as the bytes it is, into a block of
bytes — the reader for files whose contents are not
text at all, like a feather's program bytes, which
`readfile` honestly refuses. The same 16 MiB cap as
`makebytes` applies.

```nifla
writefile("note.txt", "Shalom")
let block = readbytes("note.txt")
say length(block)
say block[0]
say block[5]
```

```expected
6
83
109
```

### `astext` — the text of a block of bytes

`astext(bytes)` reads a block of bytes as text — the
road back from `readbytes`' side of the house. The
bytes are read as UTF-8, the writing that text is
kept in. A run of bytes that is not a letter stands
in the text as the replacement mark �, the way every
reader shows it — never dropped, never guessed at:

```nifla
writefile("note.txt", "Shalom")
let block = readbytes("note.txt")
say astext(block)
let marks = makebytes(3)
marks[0] = 72
marks[1] = 255
marks[2] = 105
say astext(marks)
```

```expected
Shalom
H�i
```

(Stone 28. Until this stone no word could speak a
block of bytes as text — a tool holding bytes, like
the self-made feather checker over a card, had to
build its letters one by one out of the printable
characters, and let whatever it could not build fall
away.)

### `asnumber` — a number out of text

`asnumber(text)` reads a number out of some text — the
other side of `readfile`'s coin: a file holds text, so
the number a program wrote comes back as characters,
and this turns the characters back into the number.
The accepted writing is plain: a `-` first when the
number is below zero, then digits, then — if a fraction
is wanted — one `.` and more digits. Nothing else: no
spaces, no `+`, no exponent letters.

```nifla
say asnumber("620")
say asnumber("500") + 5
say asnumber("-3.5")
```

```expected
620
505
-3.5
```

Text that isn't a number written that way is a
*problem*, in the Part 1 sense — `attempt` can catch
it, like a file that isn't there:

```nifla
attempt {
    let n = asnumber("one hundred")
    say n
} if it fails {
    say "Not a number: " + problem
}
```

```expected
Not a number: 'one hundred' is not a number 'asnumber' can read. A number is written with digits, a '-' first when it is below zero, and at most one '.' with digits after it — like 620 or -3.5.
```

(Stone 26. Until this stone the language had no such
tool — the Tutorial's capstone still teaches reading
digits by hand, with `part` and `find`, because the
building is the lesson; programs written today can
simply call `asnumber`.)

### `bitand`, `bitor`, `bitxor` — working with bits

`bitand(first, second)`, `bitor(first, second)`, and
`bitxor(first, second)` look at two whole numbers bit
by bit — a number's bits are the ones and zeros it is
counted in, place by place, the way 12 is 1100: an
eight, a four, no two, no one. A bit stands in the
answer when it stands in both numbers (`bitand`), in
either one (`bitor`), or in one but not the other
(`bitxor`):

```nifla
say bitand(12, 10)
say bitor(12, 10)
say bitxor(12, 10)
```

```expected
8
14
6
```

The tools work on whole numbers from zero up, as far
as the language's numbers stay exact — the same reach
the feather reckoning trusts. A fraction, a negative
number, or a bigger one is a *problem*, in the Part 1
sense — `attempt` can catch it:

```nifla
attempt {
    let n = bitand(3.5, 2)
    say n
} if it fails {
    say "Caught: " + problem
}
```

```expected
Caught: 'bitand' works on whole numbers — bits are counted in whole numbers — but it was given 3.5. Use a whole number, like 3 or 4.
```

(Stone 27. Until this stone the language had no word
for this work: the self-made feather checker of
Stone 25 works a byte's XOR out bit by bit by hand,
in a helper it calls `xorbyte`. Programs written
today can simply call `bitxor` — and `bitand` and
`bitor` beside it.)

(Stone 36. The words stand on bare metal too, where
they work on the machine's whole word — one
instruction each. The kernel's USB work had been
wrapping a floor block around a single AND to do
this work; now the word does it. A negative number
stops the machine there, as bare problems do — the
hosted refusal, spoken in bare metal's way.)

```nifla-bare
say bitand(12, 10)
```

### `wholediv` — dividing into whole numbers

`wholediv(first, second)` divides two whole numbers
and gives back the whole part of the quotient — the
fraction dropped, toward zero, the way Swift's whole
numbers divide. Where `/` gives the true quotient
with its fraction (17 / 5 is 3.4), `wholediv` gives
the count of whole times the second number fits into
the first:

```nifla
say wholediv(17, 5)
say wholediv(20, 5)
say wholediv(3, 7)
say wholediv(-7, 2)
```

```expected
3
4
0
-3
```

What is left over after a dividing is the first
number less the quotient times the second, counted
in the open: `17 - wholediv(17, 5) * 5` is 2.

The numbers handed to it must themselves be whole —
it is the dividing that drops the fraction, not the
numbers handed to it — and no bigger in size than
the language's numbers hold exactly, the same reach
the bit tools and the feather reckoning trust. A
fraction, or a bigger one, is a *problem*, in the
Part 1 sense — `attempt` can catch it:

```nifla
attempt {
    let n = wholediv(7, 2.5)
    say n
} if it fails {
    say "Caught: " + problem
}
```

```expected
Caught: 'wholediv' works on whole numbers — it is the dividing that drops the fraction, not the numbers handed to it — but it was given 2.5. Use a whole number, like 2 or 3.
```

Dividing by zero is the same problem `/` raises, in
the same words — and a divisor the checker can prove
is zero is refused before the program runs, the way
`/`'s is.

(Stone 30. Until this stone the language had no
single word for a whole-number quotient: the
self-made feather checker of Stone 25 reads the
whole part off a division's spoken form by hand, in
a helper it calls `floordiv`. Programs written today
can simply call `wholediv`.)

### `leftover` — what a dividing leaves

`leftover(first, second)` gives what is left of the
first number after the second has been taken out of
it `wholediv` times — the remainder of the same
dividing, counted by the same steps. It carries the
divided number's sign, the way Swift's whole numbers
leave it, and the two always add back up:
`wholediv(n, d) * d + leftover(n, d)` is `n`.

```nifla
say leftover(17, 5)
say leftover(20, 5)
say leftover(-7, 2)
say wholediv(17, 5) * 5 + leftover(17, 5)
```

```expected
2
0
-1
17
```

It asks the same of its numbers as `wholediv` does
— whole, within the exact reach, the second not
zero — and its problems speak the same words, the
checker's refusals included.

(Stone 31. Until this stone the leftover was counted
in the open, as `n - wholediv(n, d) * d` — the
self-made feather checker counts it so at every limb
of its reckoning and every digit of its counts.)

### `rounddown`, `roundup` — rounding to a whole number

`rounddown(value)` gives the whole number at or
below a number, and `roundup(value)` the whole
number at or above it. A whole number comes back
unchanged; a negative number rounds away from the
fraction it carries, so `rounddown(-2.5)` is -3 and
`roundup(-2.5)` is -2:

```nifla
say rounddown(3.5)
say roundup(3.5)
say rounddown(-2.5)
say roundup(-2.5)
```

```expected
3
4
-3
-2
```

(Stone 32. Until this stone the language had no
rounding word at all: the whole-number tools refuse
fractions, and finding the whole number at or below
one meant reading its spoken form apart — the
self-host does exactly that, by hand, to speak its
rounding messages.)

### `absolute` — a number's size

`absolute(value)` gives a number's size, never below
nothing: a below-zero number comes back with the
sign lifted off, and any other number comes back as
it is. A fraction keeps its fraction:

```nifla
say absolute(-7)
say absolute(7)
say absolute(-3.5)
say absolute(0)
```

```expected
7
7
3.5
0
```

(Stone 34. The word was first built by hand as
'absn' in the Cardnull OS calculator feather, which
reaches for a number's size at every turn of its
reckoning. Because the feather is a guest on bare
metal, the word stands on every door at once — bare
metal included, where it is proved on the emulated
screen by the bare tools proof.)

### `smallest`, `largest` — choosing between two numbers

`smallest(first, second)` gives the smaller of two
numbers, and `largest(first, second)` the larger.
Any numbers may be chosen between, fractions
included; when the two are equal, that number is
the answer either way:

```nifla
say smallest(3, 7)
say largest(3, 7)
say smallest(2.5, 2.25)
say largest(-2, -9)
```

```expected
3
7
2.25
-2
```

Together the pair is also a clamp — a number held
between two bounds, the way a window is held on a
desktop: `largest(0, smallest(place, limit))` is
never below 0 and never past the limit.

(Stone 35. The choice was spelled out with 'if',
two at a time, wherever it was wanted — the
Cardnull OS kernel does exactly that wherever it
keeps a window on the desktop, window after window.
The words stand on every door at once, bare metal
included, proved there by the bare tools proof.)

### `arguments` — the words the program was run with

`arguments()` gives the list of words that came after the
program's name on the command line. (This book's examples
are all run with the two arguments `Ada` and `Byron`.)

```nifla
let args = arguments()
say length(args)
say args[0]
say join(args, " and ")
```

```expected
2
Ada
Ada and Byron
```

### `sayerr` — speaking to the error stream

`sayerr` is `say`'s sterner sibling: it prints to the
error stream, where a program's warnings belong, so the
ordinary output stays clean.

```nifla
sayerr("Mind the step.")
say "All is well."
```

```expected
All is well.
```

The first line was spoken too — it simply went to the
other stream, which this book's examples do not show.

### `exitwith` — ending the program early, with a number

`exitwith(code)` ends the program at once, handing the
number back to whoever ran it. 0 is the number for "all
went well"; any other number says something didn't.

```nifla exit=3
say "Beginning"
exitwith(3)
say "This is never said"
```

```expected
Beginning
```

---

## Part 3 — Kinds, marks, and checked absence

### The kind words

Every value is of one *kind*: `number`, `text`, `boolean`,
`list`, `object`, or `bytes` — and there is one more,
`nothing`, the empty value, which gets its own section
below. The kind words are mostly something you *think*
with, but they can also be *written*, as marks.

### Marks — writing the kind you mean

A mark is a kind word written after a colon, on a `let`,
on a function's parameters, or after `->` on a function to
say what it gives. A mark is a promise the language checks:
at every boundary the value must be of the marked kind, or
the program is refused in plain words — before it runs,
when the checker can prove the mismatch, and at the moment
it happens, when it can't be proven ahead of time.

```nifla
let years: number = 29
make add(a: number, b: number) -> number {
    give a + b
}
say add(years, 13)
let greeting: text = "Shalom"
say greeting
```

```expected
42
Shalom
```

Marks are optional everywhere. An unmarked program is
checked just as hard in every way that doesn't need a mark;
a mark adds the kind promise on top. (One more mark shape
exists — `-> nothing` on a function that gives nothing
back — which the next section's example uses.)

### `nothing` — the empty value

`nothing` is a value: the value that says *there is
nothing here*. It can be kept, handed around, put in a
list, and compared. It speaks as `nothing`.

```nifla
let x = nothing
say x
say x == nothing
say [nothing, 1]
```

```expected
nothing
true
[nothing, 1]
```

### `maybe` — a value that is something, or nothing

A `maybe` mark promises a value of one kind *or* `nothing`:
`maybe number` is a number or nothing. This is how a
program says, honestly, "this might not be there" — a
lookup that might not find, a reading that might not have
been taken.

```nifla
make lookup(name) -> maybe number {
    if name == "Tyler" {
        give 29
    }
}
say lookup("Tyler")
say lookup("Noki")
```

```expected
29
nothing
```

A function marked `-> maybe …` that reaches its end
without `give` hands back `nothing` — the honest empty
answer, as `lookup("Noki")` shows.

### Handling both roads

A maybe value may not simply be *used* as if it were
surely there — that is the whole point of marking it. The
checker refuses, before the program runs, any use it can
prove is unhandled: adding it, comparing it for size,
handing it to a function that wants the plain kind,
giving it where the plain kind was promised. The way to
handle it is to ask, with `== nothing`, and the checker
follows the asking: on the road where the answer was
*yes*, the value is known to be nothing; on the other
road, it is known to be there, of its kind, and may be
used freely.

```nifla
make lookup(name) -> maybe number {
    if name == "Tyler" {
        give 29
    }
}
let a = lookup("Tyler")
let b = lookup("Noki")
if a == nothing {
    say "a is missing"
} else {
    say a + 1
}
if b != nothing {
    say b + 1
} else {
    say "b is missing"
}
```

```expected
30
b is missing
```

The same asking works in a `while`: `while c == nothing { … }`
leaves the loop with `c` known to be there. And the guards
stand behind the checker in any case: a maybe that slips
past every proof and is used while it is nothing is refused
at the moment of use, in plain words that say to check it
first. There is no unwrapping word to memorize — the
asking *is* the unwrapping, and both roads must be walked.

What a refusal looks like, when the checker catches an
unhandled maybe before the program runs (this program is
shown, not run — it is refused):

```text
let a: maybe number = nothing
say a + 1
```

```text
Line 2: 'a' might be nothing here — it is a number or
nothing — but '+' needs it to be a number for certain.
Check it first: if a == nothing { ... } else { ... } —
and use it in the 'else', where it is known to be there.
I caught this before the program ran, so nothing ran.
```

(The wording above is the refusal's shape; the standing
proofs carry its exact text.)


---

## Part 4 — The floor: the deliberate unsafe door

Everything above is the friendly side of the language:
managed values, every access checked, no pointers, guards
on loops and calls. It is memory-safe in the way Swift is
— that is the language's stated bar.

The *floor* is the door out of that safety, deliberately.
A floor block holds raw processor instructions (x86-64,
written the Intel way), which the compiler lays into the
program untouched and unchecked. Inside a floor block you
can touch any memory the program may touch — including
memory that isn't yours, which is exactly why the floor is
a door and not the house. Floor code runs only in
*compiled* programs: the interpreter refuses any program
that holds floor code, before anything runs, in plain
words.

A floor block is handed a *desk*, and hands answers back
on it:

- The numbers it is handed wait in an array pointed to by
  **r10** — the first at `[r10]`, the second at `[r10 + 8]`,
  and so on. **r11** says how many there are.
- One piece of text, or one block of bytes, may be handed
  too: **rbx** points at its first byte and **r12** says
  how many bytes there are.
- The block's main answer is left in **rax**. Extra answers
  may be written into a results area at **r13**, with
  **r14** saying how many — and then the block gives back
  a list of them all.

```nifla-floor
let plus = floor(41) {
    mov rax, [r10]
    add rax, 1
}
say plus
let answers = floor(100, 7) {
    mov rax, [r10]
    mov rcx, [r10 + 8]
    xor rdx, rdx
    div rcx
    mov [r13], rdx
    mov r14, 1
}
say answers
say answers[0] + answers[1]
```

```expected
42
[14, 2]
16
```

The divide gives a quotient (14, in rax) and a remainder
(2, left in the results area) at once — so the block hands
back the list `[14, 2]`. The desk's *meaning* — handed
numbers, one text or bytes, a main answer and extra
answers — is the contract on every target; the register
letters are each target's own (Part 5 and the README say
which, where a second target stands).

---

## Part 5 — Bare metal, guests, and feathers

### The bare subset

`niflac --bare` compiles a program into a binary that
boots on its own — no operating system, no runtime. Bare
metal has no heap to manage values with, so the bare
subset is sterner than the hosted language, and the
compiler refuses whatever it cannot honestly hold, in
plain words:

- Numbers are whole numbers only — the machine's own
  words. Division gives the whole quotient.
- Text can be held, measured, compared, joined, and handed
  on, but not taken apart.
- Booleans are the numbers 1 and 0 wearing their true and
  false faces.
- There are no lists and no objects on bare metal, and no
  `nothing` and no `maybe` — every value there is a machine
  word with one shape. Marks are accepted for `number`,
  `text`, `boolean`, and `bytes`, and refused for the rest.
- Blocks of bytes (`makebytes`) are there, and the floor
  is there — on bare metal the floor is how a program
  talks to the machine itself.

On bare metal, `say` writes to the machine's text screen.

### Bare-only tools

A few tools exist only on bare metal, where they name the
machine's own furniture. (The examples in this section are
compiled with `--bare` by this book's proof; they run when
the binary boots, which the language's bare suites do
every day.)

`ticks()` reads the machine's ticking count — a number
that always advances; `waittick()` sleeps until the next
tick.

```nifla-bare
let t = ticks()
waittick()
if ticks() > t {
    say "Time passed"
}
```

`readkey()` takes the next key the keyboard has offered,
as a number — 0 when no key is waiting.

```nifla-bare
let k = readkey()
if k == 0 {
    say "No key yet"
}
```

`memorysize()` tells how many bytes of memory the machine
has, from the map the loader handed over.

```nifla-bare
say memorysize()
```

The disk tools speak to an ATA disk: `disksectors()` asks
how many 512-byte sectors the drive holds, `diskread(n,
block)` reads sector `n` into a block of bytes and tells
how many bytes came, and `diskwrite(n, block)` writes a
block out to sector `n`.

```nifla-bare
let block = makebytes(512)
let got = diskread(0, block)
say disksectors()
```

### Guests — a second program through the door

A bare program built with `--bare --guest` is a *guest*:
it is linked for a doorstep address (2 MiB), ready for a
host program to lay it there and call it. The host hands
the guest one number across the desk with `callguest`,
and the guest reads it with `guestvalue()` and answers
with a parting number through `guestgive()`.

The host's side:

```nifla-bare
let back = callguest(2097152, 7)
say back
```

The guest's side:

```nifla-bare-guest
let gift = guestvalue()
guestgive(gift + 1)
```

The door's honesty, stated once and plainly: there is no
isolation. Host and guest share one privilege level and
one memory, and a faulting guest stops the whole machine.
The card a feather carries (next section) proves its bytes
are whole; it does not fence it in.

### Feathers — a guest with its card

A *feather* is a guest program together with its card,
made by the compiler in one step:

```text
niflac --bare --guest --feather welcome.nifla -o welcome.feather
feathercheck welcome.feather
```

The card stands at the feather's head, in plain text —
the program's name, what it needs, how many bytes the
program is, and the FNV-1a-64 checksum of those bytes:

```text
CARDNULL FEATHER 1
name: welcome-feather
needs: the guest door (desk version 1)
bytes: 2656
checksum: 0b2452a707571de8

<the program bytes>
```

A host's door reads the card, reckons the checksum over
the program, and lets the feather in only when they agree.
The checksum proves the bytes match the card and nothing
more — it is a card, not a signature. And anyone can run
the doorman's test: `feathercheck` (Stone 21) reads a
feather and answers in plain words whether its card is
true, as Part 1's opening showed.

### The compiler's other flags

```text
niflac --bare --video 1024x768x32 program.nifla
```

asks the loader for a picture screen of that shape, in the
multiboot way (the asking is opt-in; a program that does
not ask boots exactly as it always did). And
`--prelude file.nifla` lays a file of function definitions
under a bare program, as if they stood at its top — the
way Cardnull OS 2's kernel is built from its libraries.

```text
niflac --bare --arm program.nifla -o program.elf
```

builds the same bare subset for a second machine:
aarch64, booting on QEMU's `virt` machine (Stones 23–24).
The subset, the shapes, and the guards are the same; the
machine underneath differs, and it shows in named places.
There is no text screen, so `say` speaks over the serial
line and `readkey()` takes bytes from it; `memorysize()`
answers from the device tree the loader left behind; and
the floor desk wears this target's letters — **x19** for
the handed numbers' address, **x20** for their count,
**x21** and **x22** for the handed text or bytes and its
count, **x23** and **x24** for the results desk (0 for a
bare host, as on x86), with the block's answer left in
**x0**. With `--bare --arm --video 640x480x32` the kernel
sets up the machine's ramfb picture screen before the
program starts and leaves its address, width, height and
stride in the globals `__video_fb`, `__video_width`,
`__video_height` and `__video_stride`, where floor blocks
read them to paint. Guests, feathers, and the disk tools
belong to the x86 road for now, and an ARM build that
asks for them is refused in plain words.

---

## Where to read more

The README in this repository is the language's full
record: every stone of its building, in order, with the
design decisions and the honest limits — including the gap
ledger, which names what the checker does not yet prove
and why. The suites are the other half of the truth:
`examples/` (interpreted), `checker-examples/` (refusals),
`floor-examples/`, `voice-examples/`, and `bare-examples/`,
each with the output it must produce, and the `run-*.sh`
scripts that prove them — this book's own proof among
them.
