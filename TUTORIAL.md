# Learning Nifla — a tutorial in eleven lessons

Nifla is a small programming language that speaks in plain
words. It was made to be read: if you can read a little
JavaScript, you can read Nifla, and most of what surprises
people is how little there is to memorize.

This book is a *course*, not a reference. It assumes you
are intelligent and that you have never programmed before,
and it teaches programming itself — what a program is,
what keeping a value means, why loops exist — by building
real programs in Nifla, one small step at a time. Nothing
in it is decorative: every idea arrives because the next
program needs it, and you will run something real within
the first minutes of every lesson.

Here is the promise this course makes, plainly. You will
*write* Nifla the way you write JavaScript: type a
program, run it, see what it says — no ceremony, no
waiting. And what you write will *run* with Swift's
strength: checked before it runs, compiled to stand on
its own, honest about kinds and about nothing. And by
the end of the course you will have touched the very
same language — not a teaching dialect, not a simplified
subset for students — that an operating system, Cardnull
OS 2, is written in. The words of your first
`say "Hello, world"` are words that boot a computer.

Three habits run through the whole course:

- **One new idea at a time.** Each step adds exactly one
  thing. If a program below ever looks like two new ideas
  at once, the book has failed, not you — re-read the step
  before it.
- **Your turn, constantly.** After nearly every idea there
  is a tiny exercise. Try it before you peek: the worked
  answer stands right after it, set apart, and struggling
  for two minutes teaches more than reading for twenty.
- **One program, growing.** A single project — a *giving
  ledger*, a little book that keeps a record of gifts —
  grows quietly at the end of most lessons, one piece at a
  time. By the last lesson you will have built it entire,
  and you will recognize every piece, because you built
  each one when it was small.

The language's other book, `PRIMER.md`, is the reference
shelf: every word and every tool, one at a time. When a
lesson here leaves you wondering "what else can this word
do?", the Primer is where to look it up. This tutorial
teaches the path; the Primer keeps the whole map.

Three programs carry the language:

- `nifla program.nifla` — checks a program, then runs it.
- `niflac program.nifla` — checks it, then compiles it
  into a program that stands on its own. With `--bare` it
  compiles a smaller, sterner subset of the language into
  a binary that boots on bare metal, with no operating
  system underneath; with `--bare --guest --feather` it
  makes a *feather* — a guest program with its card laid
  on it, the form a host's door receives (Lesson 9).
- `feathercheck program.feather` — reads a feather and
  answers, in plain words, whether its card is true.

In this repository, one command builds all three:

```text
./build.sh
```

That leaves `./nifla`, `./niflac`, and `./feathercheck`
standing in the folder, ready to use.

Every example in this book is real. A standing proof
(`run-tutorial.sh`) takes each program out of the book
and runs it — interpreted, and compiled where it can be —
and the proof fails if any program's output drifts from
what the book says. The proof runs every example with the
same two program arguments, `Ada` and `Byron` (Lesson 8
shows what program arguments are), and it runs each
example in a fresh, empty folder, so the lessons that
write files (Lesson 6 onward) always start in an empty
room — on your own machine, those files will still be
there the second time you run the program, and that
difference is itself one of the lessons.

A word about errors, before we start: when a Nifla
program goes wrong, the language answers in plain words,
with the line number, and tries to say what would fix it.
And before a program runs at all, a *checker* reads it
and refuses — in the same plain words — programs it can
prove will go wrong in certain ways. You will meet the
checker properly in Lesson 5. It is a kind character in
this story: it would rather stop you at the door, with an
explanation, than let you fall down the stairs.

---

## Lesson 1 — Saying and keeping

### Step 1: your first program

Every programmer's first program, in every language,
says hello to the world. Here is yours. Type it into a
file called `hello.nifla`:

```nifla
say "Hello, world"
```

```expected
Hello, world
```

Now run it:

```text
./nifla hello.nifla
```

and the machine answers: `Hello, world`.

Stop and notice what just happened, because it is the
whole shape of programming: you wrote an instruction;
the machine followed it exactly. `say` is the language's
word for speaking — hand it a value and it prints the
value and a new line. The words between the double
quotes are *text*: written words kept as a value.

Notice how little ceremony there was: no setup, no
compiling, no waiting — write it, run it, read what it
says. That quickness is the JavaScript half of Nifla's
promise, and the early lessons live there. The other
half is waiting in Lesson 8, and it is worth the walk.

**Your turn.** Make the program say your own name
instead. One word changes.

#### The worked answer

```nifla
say "Tyler"
```

```expected
Tyler
```

### Step 2: keeping a value

A program that only repeats what it was told is a
parrot. Programs get interesting when they *keep*
things. `let` gives a value a name:

```nifla
let name = "Tyler"
say name
```

```expected
Tyler
```

A name with a value kept in it is what programmers call
a *variable*. Think of it as a labeled shelf: the label
stays, and what stands on the shelf can change. After
`let`, the name can be used anywhere the value could.

**Your turn.** Keep the text "Shalom" on a shelf called
`greeting`, then say what is on the shelf.

#### The worked answer

```nifla
let greeting = "Shalom"
say greeting
```

```expected
Shalom
```

### Step 3: building a sentence

Joining text with `+` speaks the other side into the
text, whatever it is. That is how a program builds a
sentence out of pieces — some kept on shelves, some
written on the spot:

```nifla
let name = "Tyler"
say "I am " + name + "."
```

```expected
I am Tyler.
```

**Your turn.** Keep a town on a shelf called `town` —
any town you like — and say the sentence "I live in "
followed by the town and a full stop, all in one `say`.

#### The worked answer

```nifla
let town = "Washington"
say "I live in " + town + "."
```

```expected
I live in Washington.
```

### Step 4: numbers, and a shelf that changes

Numbers are kept the same way, and reckoned with `+`,
`-`, `*`, and `/`. And a shelf's contents can be
replaced with a plain `=`:

```nifla
let years = 29
say years * 365
years = years + 1
say years
```

```expected
10585
30
```

Read the middle line slowly: `years = years + 1` takes
what is on the `years` shelf, adds one, and puts the
answer back on the same shelf. (The 10585 is a small
honest lie worth noticing: 29 × 365 counts the years in
days *without* leap days. Programs reckon exactly what
you tell them to — no more, no less. Saying precisely
what you mean is most of the craft.)

**Your turn.** Keep the number 7 on a shelf called
`loaves`. Say the shelf doubled, then put three more
loaves on the shelf and say the shelf again.

#### The worked answer

```nifla
let loaves = 7
say loaves * 2
loaves = loaves + 3
say loaves
```

```expected
14
10
```

### The ledger grows: one gift, said out loud

Here is the first piece of the course's project. A
*giving ledger* is a little book that records gifts —
who they went to, and how much, kept in exact cents so
nothing is ever rounded. (A real tally this book's
first reader keeps works exactly so.) Its first piece
is just one gift, kept and said:

```nifla
let who = "Feeding America"
let cents = 620
say who + ": " + cents + " cents"
```

```expected
Feeding America: 620 cents
```

Notice the number `cents` was spoken into the sentence
by the `+`, exactly as `name` was. That one line — a
name, an amount, a sentence — is the seed of the whole
ledger.

### Your turn

Keep your own name and the year you were born on two
shelves. Say your name, then work out — from the year
on the shelf, not from a number you reckon in your
head — how old you turn in 2026, and say that.

#### The worked answer

```nifla
let name = "Miriam"
let born = 1990
say name
say 2026 - born
```

```expected
Miriam
36
```

### You can now…

- write a program and run it with `nifla`;
- speak any value with `say`;
- keep a value on a named shelf with `let`, and change
  what the shelf holds with `=`;
- build a sentence by joining text with `+`, speaking
  numbers into it as you go;
- reckon with `+`, `-`, `*`, and `/`.

Two small things to carry forward: lines that begin
with `//` are *comments* — notes to the reader that the
language steps over. And a name made inside a pair of
braces `{ }` belongs to that stretch of the program and
is not seen outside it. You will meet braces in the
very next lesson.

---

## Lesson 2 — Deciding and repeating

### Step 1: asking a question

A parrot repeats; a program *decides*. A comparison
asks a question and answers `true` or `false`: `==`
(is it the same), `!=` (is it different), `<`, `<=`,
`>`, `>=`:

```nifla
say 3 == 3
say 3 != 3
say 2 < 5
say "apple" == "apple"
```

```expected
true
false
true
true
```

One warning to file away: values of different kinds
are never equal — the number 3 is not the text "3" —
so a question always compares like with like.

**Your turn.** Ask two questions: is 10 greater than 7,
and is "bread" the same as "bread"? Say both answers.

#### The worked answer

```nifla
say 10 > 7
say "bread" == "bread"
```

```expected
true
true
```

### Step 2: walking the road the answer opens

`if` runs a stretch of code when its question answers
true, and `else` — when there is one — runs the other
stretch when it answers false. The stretch lives
between braces. Here is a door-keeper:

```nifla
let years = 29
if years >= 18 {
    say "Come in - you are grown."
} else {
    say "Wait a little longer."
}
```

```expected
Come in - you are grown.
```

Change the 29 to 12 in your own copy and run it again:
the other road is taken. The program did not get
smarter; it *asked*, and walked the road the answer
opened.

**Your turn.** Keep a number of coins on a shelf. If
there are at least 100, say "A full purse." Otherwise
say "Still gathering." Try it with 250.

#### The worked answer

```nifla
let coins = 250
if coins >= 100 {
    say "A full purse."
} else {
    say "Still gathering."
}
```

```expected
A full purse.
```

### Step 3: again, while a question holds

Deciding once is half the craft. The other half is
repeating. `while` repeats its stretch as long as its
question keeps answering true:

```nifla
let n = 3
while n >= 1 {
    say n
    n = n - 1
}
say "Go"
```

```expected
3
2
1
Go
```

Read it as a story: `n` starts at 3; the question "is
n still at least 1?" is asked before every round;
inside, the program says `n` and then makes `n`
smaller — and that making-smaller is what lets the
loop ever end. A loop whose question never turns false
would run forever, so the language stands guard: a
program whose loops pass a million times without
finishing is stopped and told so, in plain words.

**Your turn.** Count up instead of down: start at 1 and
say 1, 2, 3, 4, 5, one per line, with a `while`.

#### The worked answer

```nifla
let n = 1
while n <= 5 {
    say n
    n = n + 1
}
```

```expected
1
2
3
4
5
```

### Step 4: again, a counted number of times

When the number of rounds is known ahead of time,
`repeat` says it outright. Here it builds a row of
stars one star at a time — text can grow on a shelf
just like a number can:

```nifla
let row = ""
repeat 5 {
    row = row + "*"
}
say row
```

```expected
*****
```

**Your turn.** Build a row of 8 dashes the same way,
and say it.

#### The worked answer

```nifla
let row = ""
repeat 8 {
    row = row + "-"
}
say row
```

```expected
--------
```

### Step 5: walking a row of things

A *list* is a row of values written between `[ ]`.
`for … in` walks a list, taking each item in turn under
a name:

```nifla
let names = ["Ada", "Byron", "Caleb"]
for name in names {
    say "Hello, " + name
}
say "That is " + length(names) + " friends."
```

```expected
Hello, Ada
Hello, Byron
Hello, Caleb
That is 3 friends.
```

(`length` counts the items in a list. It is a *toolbox*
word, and the toolbox gets a lesson of its own next;
lists get one too. For now: a list is a row of values,
and `for` visits each one.)

**Your turn.** Walk the list `["sun", "moon", "stars"]`
and say "I see the " before each one.

#### The worked answer

```nifla
let things = ["sun", "moon", "stars"]
for thing in things {
    say "I see the " + thing
}
```

```expected
I see the sun
I see the moon
I see the stars
```

### Putting it together: the greeter that checks its work

```nifla
let names = ["Ada", "Byron", "Caleb"]
let greeted = 0
for name in names {
    say "Hello, " + name
    greeted = greeted + 1
}
if greeted == length(names) {
    say "Everyone was greeted."
}
```

```expected
Hello, Ada
Hello, Byron
Hello, Caleb
Everyone was greeted.
```

The counter `greeted` is the program keeping a tally
on a shelf while it works — the seed of every ledger,
score, and total you will ever write.

### The ledger grows: a first total

The ledger's gifts, kept for now as a row of amounts,
and added up by walking the row:

```nifla
let amounts = [620, 500, 1342]
let total = 0
for cents in amounts {
    total = total + cents
}
say "Total so far: " + total + " cents"
```

```expected
Total so far: 2462 cents
```

Three gifts, one walk, one total. The amounts have no
names attached yet — the next lesson fixes that.

### Your turn

Use `while` to print the 3-times table from 1 to 5,
one line per round, in this shape: `3 x 1 = 3`. Let
the program reckon the answers — do not type them
yourself.

#### The worked answer

```nifla
let n = 1
while n <= 5 {
    say "3 x " + n + " = " + (3 * n)
    n = n + 1
}
```

```expected
3 x 1 = 3
3 x 2 = 6
3 x 3 = 9
3 x 4 = 12
3 x 5 = 15
```

### You can now…

- ask questions with `==`, `!=`, `<`, `<=`, `>`, `>=`,
  and get `true` or `false` answers;
- walk one of two roads with `if` and `else`;
- repeat while a question holds, with `while`;
- repeat a counted number of times, with `repeat`;
- walk a list item by item with `for … in`;
- keep a running tally while a loop works.

---

## Lesson 3 — Keeping many things

### Step 1: a row of values, reached by number

Real programs rarely keep one thing; they keep rows of
things. A *list* is a row of values between `[ ]`,
separated by commas. Items are numbered from 0 — the
first item is `list[0]` — and `list[i]` reaches one
item. Here is a garden, kept as a list of its rows:

```nifla
let rows = ["beans", "collards", "lettuce"]
say rows[0]
say rows[2]
rows[1] = "kale"
say rows
```

```expected
beans
lettuce
["beans", "kale", "lettuce"]
```

Reaching a shelf inside the row works with the same
`=` as any shelf: `rows[1] = "kale"` replaced the
second item. Reaching *past* the end of a list is
refused in plain words that say how many items there
are — try `say rows[9]` in your own copy and read the
refusal; it is your first, and it is kind.

**Your turn.** Keep a list of three colors. Say the
last one — remember, the counting starts at 0, so the
last of three is number 2.

#### The worked answer

```nifla
let colors = ["red", "green", "blue"]
say colors[2]
```

```expected
blue
```

### Step 2: the toolbox

The *toolbox* is the set of tools a program calls by
name, like functions that were always there. Each is
handed values in parentheses and hands one value back.
Hand a tool the wrong kind of value and it refuses in
plain words, naming the tool and showing how it is
called. You have already used two: `length`, which
counts, and `append`, which adds one item to the end
of a list:

```nifla
let rows = ["beans", "collards", "lettuce"]
append(rows, "scallions")
say length(rows)
say rows
```

```expected
4
["beans", "collards", "lettuce", "scallions"]
```

**Your turn.** Start with the list `[10, 20]`, append
30 to it, and say how many items it holds now.

#### The worked answer

```nifla
let numbers = [10, 20]
append(numbers, 30)
say length(numbers)
```

```expected
3
```

### Step 3: text, taken apart and put together

Three tools do most of the everyday text work.
`sorted` hands back a *new* list in order (the list it
was given is left as it was). `join` speaks every item
of a list and joins the spoken forms with a separator
between them. `split` is join's way back — it cuts
text at every separator and gives back the pieces:

```nifla
let shopping = ["rice", "beans", "apples"]
say sorted(shopping)
say join(shopping, ", ")
let words = split("rice, beans, apples", ", ")
say words[1]
```

```expected
["apples", "beans", "rice"]
rice, beans, apples
beans
```

**Your turn.** Cut the text "sun-moon-stars" at its
dashes with `split`, and say the middle piece.

#### The worked answer

```nifla
let pieces = split("sun-moon-stars", "-")
say pieces[1]
```

```expected
moon
```

Two smaller tools finish the set. `find` gives the
character number where a piece of text first appears,
counting from 0 — or -1 when it is not there at all.
`part` takes a piece of text: `part(text, start,
count)`:

```nifla
say find("garden", "den")
say find("garden", "xyz")
say part("garden", 0, 3)
```

```expected
3
-1
gar
```

**Your turn.** Use `part` to take the last two
characters of "Tyler" — they start at character 3.

#### The worked answer

```nifla
say part("Tyler", 3, 2)
```

```expected
er
```

### Step 4: a card of facts

An *object* is the other shape of keeping: values with
named fields, written between `{ }`, each field a name,
a colon, and a value. `plant.name` reaches a field, and
a field can be given — or given for the first time —
with the same dot:

```nifla
let plant = { name: "yardlong beans", watered: true }
say plant.name
plant.watered = false
say plant
say fieldnames(plant)
```

```expected
yardlong beans
{ name: "yardlong beans", watered: false }
["name", "watered"]
```

Fields keep the order they were first given, as the
spoken form shows, and `fieldnames` lists them. A list
answers "what stands in the row?"; an object answers
"what do we know about this one thing?"

**Your turn.** Make an object for a dog: a `name`
field and an `age` field. Say the dog's name, then
give the dog a brand-new field, `good`, set to `true`,
and say the whole object.

#### The worked answer

```nifla
let dog = { name: "Sadie", age: 4 }
say dog.name
dog.good = true
say dog
```

```expected
Sadie
{ name: "Sadie", age: 4, good: true }
```

### The ledger grows: gifts with names

Now the amounts from Lesson 2 get their names. Each
gift becomes an object — who it went to, how many
cents — and the book becomes a list of those objects.
A list of objects is how most real keeping is done:

```nifla
let gifts = []
append(gifts, { who: "Feeding America", cents: 620 })
append(gifts, { who: "Barry Cunningham", cents: 500 })
append(gifts, { who: "Feeding America", cents: 1342 })
for gift in gifts {
    say gift.who + ": " + gift.cents + " cents"
}
```

```expected
Feeding America: 620 cents
Barry Cunningham: 500 cents
Feeding America: 1342 cents
```

The total is missing — on purpose. Adding gifts and
totalling them is work the ledger will do again and
again, and work done again and again deserves a tool
of its own. That is the next lesson.

### Your turn

Here are three tools out of order: "shovel", "hoe",
"rake". Keep them in a list, print the list sorted,
and then print the second tool in the sorted order.

#### The worked answer

```nifla
let tools = ["shovel", "hoe", "rake"]
let inOrder = sorted(tools)
say inOrder
say inOrder[1]
```

```expected
["hoe", "rake", "shovel"]
rake
```

### You can now…

- keep a row of values in a list, reach items by
  number from 0, and replace them;
- grow a list with `append` and count it with
  `length`;
- sort with `sorted`, join with `join`, cut text with
  `split`, search with `find`, and take pieces with
  `part`;
- keep a card of named facts in an object, reach and
  add fields with the dot, and list them with
  `fieldnames`;
- weave the two together: a list of objects.

---

## Lesson 4 — Making your own tools

### Step 1: a stretch of code with a name

The toolbox tools were always there. The moment a
program grows past a page, you start wanting tools of
your own: a stretch of code with a name, that you can
hand values to and that hands one value back. That is
a *function*, and `make` builds one. `give` is how a
function hands its answer back:

```nifla
make greet(name) {
    give "Hello, " + name + "."
}
say greet("Noki")
say greet("Ada")
```

```expected
Hello, Noki.
Hello, Ada.
```

The name in the parentheses is the function's
*parameter* — its own shelf, filled fresh by whoever
calls it. One function, any number of calls, each with
its own filling.

**Your turn.** Make a function `farewell` that is
handed a name and gives back "Goodbye, " joined with
the name and a full stop. Call it on "Byron".

#### The worked answer

```nifla
make farewell(name) {
    give "Goodbye, " + name + "."
}
say farewell("Byron")
```

```expected
Goodbye, Byron.
```

### Step 2: a function that reckons

```nifla
make twice(n) {
    give n * 2
}
say twice(21)
say twice(5)
```

```expected
42
10
```

**Your turn.** Make `half`, which gives back its number
divided by 2, and say `half(10)`.

#### The worked answer

```nifla
make half(n) {
    give n / 2
}
say half(10)
```

```expected
5
```

### Step 3: a function with a loop inside

Anything a program can do, a function can do — loops
included. This one builds a row of stars of any length:

```nifla
make line(n) {
    let row = ""
    repeat n {
        row = row + "*"
    }
    give row
}
say line(3)
say line(7)
```

```expected
***
*******
```

Notice `let row` lives *inside* the function: each
call gets a fresh shelf, so two calls never trip over
each other. Names made inside a function's braces
belong to that call alone.

**Your turn.** Make `dashes(n)` the same way, building
a row of dashes, and say `dashes(4)`.

#### The worked answer

```nifla
make dashes(n) {
    let row = ""
    repeat n {
        row = row + "-"
    }
    give row
}
say dashes(4)
```

```expected
----
```

### Step 4: a function that walks a list

```nifla
make average(numbers) {
    let total = 0
    for n in numbers {
        total = total + n
    }
    give total / length(numbers)
}
say average([10, 20, 30])
say average([3, 5])
```

```expected
20
4
```

**Your turn.** Make `sum(numbers)` — the same walk
without the dividing — and say `sum([1, 2, 3, 4])`.

#### The worked answer

```nifla
make sum(numbers) {
    let total = 0
    for n in numbers {
        total = total + n
    }
    give total
}
say sum([1, 2, 3, 4])
```

```expected
10
```

### Putting it together: tools calling on tools

Functions that call on other functions are how big
programs are built out of small, trustworthy pieces:

```nifla
make line(n) {
    let row = ""
    repeat n {
        row = row + "*"
    }
    give row
}
make average(numbers) {
    let total = 0
    for n in numbers {
        total = total + n
    }
    give total / length(numbers)
}
let scores = [8, 9, 7]
say line(12)
say "Average score: " + average(scores)
say line(12)
```

```expected
************
Average score: 8
************
```

You have been writing a library without being told:
`greet`, `twice`, `line`, `average` are *your* toolbox
now, and any program you write can carry them at its
top and call on them below. That is the whole secret
of large programs — they are small programs, kept in
functions, all the way down.

One thing to keep in your pocket: a function that
reaches its end without `give` hands back *nothing at
all*. The next lesson makes that matter.

### The ledger grows: the book gets its tools

```nifla
make addgift(gifts, who, cents) {
    append(gifts, { who: who, cents: cents })
}
make total(gifts) {
    let sum = 0
    for gift in gifts {
        sum = sum + gift.cents
    }
    give sum
}
let gifts = []
addgift(gifts, "Feeding America", 620)
addgift(gifts, "Barry Cunningham", 500)
addgift(gifts, "Feeding America", 1342)
for gift in gifts {
    say gift.who + ": " + gift.cents + " cents"
}
say "Total: " + total(gifts) + " cents"
```

```expected
Feeding America: 620 cents
Barry Cunningham: 500 cents
Feeding America: 1342 cents
Total: 2462 cents
```

Two things to notice. `addgift` never says `give` — it
does its work by growing the list it was handed (lists
are shared: a change made through one name is seen
through every name), and hands nothing back. And
`total` walks the same list the Lesson 2 thread walked
— but now the walk has a name, and the book will never
have to write it again.

### Your turn

Make a tool called `firstandlast`. It is handed a list
and gives back its first and last items joined with
" and ". Use it on `["sun", "moon", "stars"]`.

#### The worked answer

```nifla
make firstandlast(items) {
    give items[0] + " and " + items[length(items) - 1]
}
say firstandlast(["sun", "moon", "stars"])
```

```expected
sun and stars
```

### You can now…

- build a function with `make`, hand it values through
  parameters, and hand an answer back with `give`;
- put loops and lists inside functions, each call with
  fresh shelves of its own;
- grow a personal library of tools and build programs
  out of them;
- add to a shared list from inside a function that
  gives nothing back.

---

## Lesson 5 — Kinds and nothing

### Step 1: saying the kind out loud

Every value is of one *kind*: `number`, `text`,
`boolean`, `list`, `object`, or `bytes` — and there is
one more, `nothing`, which gets Step 2. A kind can be
*written*, as a mark: a kind word after a colon, on a
`let`, on a function's parameters, or after `->` on a
function to say what it gives. A mark is a promise the
language checks — at every boundary the value must be
of the marked kind, or the program is refused in plain
words:

```nifla
let years: number = 29
make double(n: number) -> number {
    give n * 2
}
say double(years)
let word: text = "Shalom"
say word
```

```expected
58
Shalom
```

Marks are optional everywhere; an unmarked program is
checked just as hard in every way that doesn't need a
mark. A mark adds the kind promise on top.

**Your turn.** Keep a `text` mark on a shelf holding
your name, and mark a function `triple` so it promises
a number in and a number out. Say `triple(4)`.

#### The worked answer

```nifla
let name: text = "Tyler"
make triple(n: number) -> number {
    give n * 3
}
say name
say triple(4)
```

```expected
Tyler
12
```

### Step 2: nothing, and maybe

`nothing` is a value: the value that says *there is
nothing here*. It can be kept, handed around, and
compared, and it speaks as `nothing`. Why would a
program hold nothing on purpose? Because the honest
answer to some questions is "it isn't there" — a
lookup that might not find.

A `maybe` mark promises a value of one kind *or*
`nothing`: `maybe number` is a number or nothing. Here
is a lookup with an honest empty answer:

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

Look at how the nothing arrived: on the road where the
name is not "Tyler", `lookup` reaches its end without
`give` — so it hands back `nothing`. (Lesson 4's
pocket, opened: a function that gives nothing back
gives *nothing* back. The `-> maybe` mark makes that a
promise instead of an accident.)

**Your turn.** Write `ageOf` the same way: it knows
one person — "Ada" is 36 — and says nothing for anyone
else. Say `ageOf("Ada")` and `ageOf("Caleb")`.

#### The worked answer

```nifla
make ageOf(name) -> maybe number {
    if name == "Ada" {
        give 36
    }
}
say ageOf("Ada")
say ageOf("Caleb")
```

```expected
36
nothing
```

### Step 3: handling both roads

A maybe value may not simply be *used* as if it were
surely there — that is the whole point of marking it.
The way to handle it is to ask, with `== nothing`, and
the checker follows the asking: on the road where the
answer was *yes*, the value is known to be nothing; on
the other road, it is known to be there, of its kind,
and may be used freely. The asking *is* the unwrapping
— there is no other word to memorize:

```nifla
make lookup(name) -> maybe number {
    if name == "Tyler" {
        give 29
    }
}
let a = lookup("Tyler")
if a == nothing {
    say "No age on file."
} else {
    say "Next year: " + (a + 1)
}
let b = lookup("Noki")
if b != nothing {
    say "Next year: " + (b + 1)
} else {
    say "No age on file."
}
```

```expected
Next year: 30
No age on file.
```

**Your turn.** Using your `ageOf` from Step 2, look up
"Caleb" and handle both roads: if it is nothing, say
"Unknown."; otherwise say the age doubled.

#### The worked answer

```nifla
make ageOf(name) -> maybe number {
    if name == "Ada" {
        give 36
    }
}
let age = ageOf("Caleb")
if age == nothing {
    say "Unknown."
} else {
    say age * 2
}
```

```expected
Unknown.
```

### Step 4: meet the checker

Now watch the checker work. This program is *shown,
not run*, because the checker refuses it before
anything runs:

```text
make lookup(name) -> maybe number {
    if name == "Tyler" {
        give 29
    }
}
let b = lookup("Noki")
say b + 1
```

```text
Line 7: This uses a number or nothing — a value that
may be nothing — where a value that is surely there is
needed, and nothing is the empty value: there is
nothing there to use. Check the value first, like:
if value == nothing { ... } else { ... } — in the
'else', the value is known to be there. I caught this
before the program ran, so nothing ran.
```

Those are the checker's own words, from a real refusal.
Read what it did for you: it read the whole program
*before* running it, found the one line where a maybe
value was used as if it were surely there, stopped
everything, named the line, explained the problem in
plain words, and showed the shape of the fix. That is
safety you can feel — not a fence you crash into, but a
friend at the door who reads your work and says "this
one line, here; walk both roads." The guards stand
behind the checker, too: a maybe that somehow slips
past every proof and is used while it is nothing is
refused at the moment of use, in the same plain words.

This is the Swift half of the promise, arriving early:
strength that checks your work *before* it runs, the
way a compiled language's does — while you are still
writing as freely as JavaScript. You do not have to
choose between the two halves. In Nifla they arrive
together.

### The ledger grows: finding a gift

The book learns to answer "what did we give to…?" —
honestly, including when the answer is *nothing is in
the book*:

```nifla
make findgift(gifts, who) -> maybe object {
    for gift in gifts {
        if gift.who == who {
            give gift
        }
    }
}
let gifts = []
append(gifts, { who: "Feeding America", cents: 620 })
append(gifts, { who: "Barry Cunningham", cents: 500 })
let found = findgift(gifts, "Barry Cunningham")
if found == nothing {
    say "No gift to Barry Cunningham is in the book."
} else {
    say "Barry Cunningham: " + found.cents + " cents"
}
let missing = findgift(gifts, "Noki")
if missing == nothing {
    say "No gift to Noki is in the book."
}
```

```expected
Barry Cunningham: 500 cents
No gift to Noki is in the book.
```

The mark says `-> maybe object` — a gift card, or
nothing. Both lookups walk both roads, and the book
never pretends.

### Your turn

Write a phone book as a function `numberFor` that is
handed a name and gives back `maybe text`: "Mom" gives
"555-0100" and "Billy" gives "555-0125". Look up Billy
and look up Quinton, handling both roads for each.

#### The worked answer

```nifla
make numberFor(name) -> maybe text {
    if name == "Mom" {
        give "555-0100"
    }
    if name == "Billy" {
        give "555-0125"
    }
}
let found = numberFor("Billy")
if found == nothing {
    say "No number for Billy."
} else {
    say "Billy: " + found
}
let missing = numberFor("Quinton")
if missing == nothing {
    say "No number for Quinton."
} else {
    say "Quinton: " + missing
}
```

```expected
Billy: 555-0125
No number for Quinton.
```

### You can now…

- write kind marks on shelves, parameters, and
  function promises, and have the language check them;
- say `nothing` — the honest empty value — and promise
  "this kind, or nothing" with `maybe`;
- handle both roads by asking `== nothing`, the asking
  being the unwrapping;
- read a checker refusal and know what it is telling
  you: the line, the problem, the shape of the fix.

---

## Lesson 6 — Papers that stay

### Step 1: writing and reading a file

Everything so far has lived and died inside one run of
a program; when the program ends, its shelves are
swept clean. But a program can also keep *papers*:
files on the disk, which stay after the program ends.
`writefile(path, text)` writes text to a file,
replacing what was there. `readfile(path)` gives back
a file's whole text:

```nifla
writefile("note.txt", "Shalom, garden")
let back = readfile("note.txt")
say back
say length(back)
```

```expected
Shalom, garden
14
```

**Your turn.** Write the text "Remember the milk" to a
file called `reminder.txt`, read it back onto a shelf,
and say the shelf.

#### The worked answer

```nifla
writefile("reminder.txt", "Remember the milk")
let back = readfile("reminder.txt")
say back
```

```expected
Remember the milk
```

### Step 2: reading a file as bytes

There is a second reader, for files whose contents are
not text at all. `readbytes(path)` reads a file as the
bytes it is, into a block of *bytes* — the language's
way of holding raw data, where each byte is a whole
number from 0 to 255, reached by number like a list
item:

```nifla
writefile("note.txt", "Shalom")
let block = readbytes("note.txt")
say length(block)
say block[0]
```

```expected
6
83
```

The 83 is the byte that writes the letter "S". Hold
that thought loosely — bytes matter most downstairs,
in Lesson 10, and on feathers, in Lesson 9. Here, what
matters is the shape of the idea: text is for reading,
bytes are for exactness.

**Your turn.** Write "Hi" to a file, read it back as
bytes, and say how many bytes there are and what the
second byte is. (The byte for "i" is 105.)

#### The worked answer

```nifla
writefile("hi.txt", "Hi")
let block = readbytes("hi.txt")
say length(block)
say block[1]
```

```expected
2
105
```

### Step 3: a program that remembers

Now the real lesson: a program that remembers between
runs. A guest book, which anyone running the program
signs:

```nifla
let names = []
attempt {
    let saved = readfile("guestbook.txt")
    if saved != "" {
        names = split(saved, "\n")
    }
} if it fails {
    say "A brand-new guest book."
}
append(names, arguments()[0])
writefile("guestbook.txt", join(names, "\n"))
say "The guest book holds " + length(names) + " name(s)."
say join(names, ", ")
```

```expected
A brand-new guest book.
The guest book holds 1 name(s).
Ada
```

Walk it through. The program starts with an empty
list, then *tries* to read the guest book from last
time. That trying is `attempt`: it runs a stretch, and
if a problem arises inside it — and a file that is not
there is a problem — the `if it fails` stretch runs
instead. On the very first run there is no book, so
the program says so and carries on with the empty
list. Then it signs the book with the first word it
was run with (`arguments()` — Lesson 8 gives it its
full story), writes the whole book back as one name
per line, and reports.

Run it twice on your own machine: the second run finds
the book, and Ada is joined by whoever signs next. The
program has a memory now — not in itself, but in its
papers. (This book's proof runs each example in a
fresh folder, so in these pages the book is always
new; the remembering happens on *your* machine, and
watching it happen is the lesson.)

**Your turn.** Change one thing in your own copy: make
the guest book's file called `visitors.txt` instead,
and the fresh-start message say "A brand-new visitors
book." Run it and check the first line.

#### The worked answer

```nifla
let names = []
attempt {
    let saved = readfile("visitors.txt")
    if saved != "" {
        names = split(saved, "\n")
    }
} if it fails {
    say "A brand-new visitors book."
}
append(names, arguments()[0])
writefile("visitors.txt", join(names, "\n"))
say "The visitors book holds " + length(names) + " name(s)."
say join(names, ", ")
```

```expected
A brand-new visitors book.
The visitors book holds 1 name(s).
Ada
```

`attempt` gets a fuller telling in the next lesson —
it is the language's answer to everything that can go
wrong along the way. Here it did its quietest work:
turning "there is nothing here yet" from a crash into
a beginning.

### The ledger grows: the book is written down

The ledger learns to keep its papers. For now the book
is saved as one line per gift — who, a bar, the cents —
and read back whole:

```nifla
let gifts = []
append(gifts, { who: "Feeding America", cents: 620 })
append(gifts, { who: "Barry Cunningham", cents: 500 })
let lines = []
for gift in gifts {
    append(lines, gift.who + "|" + gift.cents)
}
writefile("ledger.txt", join(lines, "\n"))
let back = readfile("ledger.txt")
say back
say "Lines in the book: " + length(split(back, "\n"))
```

```expected
Feeding America|620
Barry Cunningham|500
Lines in the book: 2
```

Honesty requires a note: what came back is *text*.
The names read fine, but the cents came back as the
characters "620", not the number 620 — papers hold
text, and text is all a file can promise. Teaching the
program to read its own numbers back is the
capstone's last trick, in Lesson 11. Until then, the
book is written down, and that is already something:
it survives the program that wrote it.

### Your turn

Make a verse keeper. Write this line to a file called
`verse.txt` — "Your word is a lamp to my feet, and a
light for my path." — then read the file back and say
what it holds.

#### The worked answer

```nifla
writefile("verse.txt", "Your word is a lamp to my feet, and a light for my path.")
let verse = readfile("verse.txt")
say verse
```

```expected
Your word is a lamp to my feet, and a light for my path.
```

### You can now…

- write text to a file with `writefile` and read a
  file's whole text back with `readfile`;
- read a file as exact bytes with `readbytes`;
- try something that might not be there with
  `attempt … if it fails`, and carry on kindly when
  it isn't;
- build a program that remembers between runs, in its
  papers.

---

## Lesson 7 — When things go wrong

### Step 1: the two tenses of trouble

Things go wrong in two tenses. Some problems can be
proven *before* the program runs — those are the
checker's, and you met it in Lesson 5. The rest only
arise along the way: a file that is not there, a
division by a number that turned out to be zero. Those
belong to `attempt`, which you borrowed in Lesson 6.
Here is its full story.

`attempt` runs a stretch, and if a problem arises
inside it, the `if it fails` stretch runs instead,
with the problem's own words waiting in the name
`problem`:

```nifla
attempt {
    let zero = length("")
    say 10 / zero
} if it fails {
    say "That sum went wrong: " + problem
}
say "The program carries on."
```

```expected
That sum went wrong: I can't divide by zero. Dividing needs a second number that isn't zero.
The program carries on.
```

Notice the zero here was *worked out while the program
ran* — `length("")` is 0, but nothing in the program
says so in so many words, so the checker cannot prove
it ahead of time. The problem arose honestly, along
the way, and `attempt` caught it, and the program
carried on.

**Your turn.** Try dividing 7 by a worked-out zero of
your own — `length("ab") - 2` is one — and in the
failure stretch, say "Caught it." Then say "Still
standing." after the whole attempt.

#### The worked answer

```nifla
attempt {
    let zero = length("ab") - 2
    say 7 / zero
} if it fails {
    say "Caught it."
}
say "Still standing."
```

```expected
Caught it.
Still standing.
```

### Step 2: the other tense

A zero written plainly — `10 / 0` — is the other
tense: the checker proves it before the program starts
and refuses the whole program, and `attempt` never
gets the chance. The two of them work together: the
checker catches what can be proven ahead of time, and
`attempt` catches the rest, as it happens. Neither is
a punishment. Both are the language refusing to let a
program lie about what it is doing.

### Step 3: the program's second voice

A program also has two voices. `say` speaks to the
ordinary output; its sterner sibling `sayerr` speaks
to the *error stream*, where warnings belong, so the
ordinary output stays clean:

```nifla
sayerr("Mind the step.")
say "All is well."
```

```expected
All is well.
```

The first line was spoken too — it simply went to the
other stream, which this book's examples do not show.
When you run that program yourself, your terminal will
show both lines; they arrived by different roads.

**Your turn.** Send the warning "Low bridge." to the
error stream, and say "Through." to the ordinary one.

#### The worked answer

```nifla
sayerr("Low bridge.")
say "Through."
```

```expected
Through.
```

### Step 4: reading a refusal

Most errors you will ever meet are neither deep nor
dramatic. They are small, and the language's plain
words make them easy to find. This program is shown,
not run — read its refusal:

```text
let mesage = "Shalom"
say message
```

```text
Line 2: I don't know a variable called 'message' yet.
You can make one with: let message = ...
Did you mean 'mesage'?
```

One letter out of place, and the language not only
found it but guessed what you meant. That is the
spirit of every refusal in this language: name the
line, say the problem plainly, point at the fix. When
you meet one — and you will, everyone does — read it
slowly. It is almost always telling you the truth.

### The ledger grows: a book that survives a missing file

The ledger puts the two tenses to work. Reading its
papers is wrapped in `attempt`, so the very first run
— no file yet — is a beginning, not a crash:

```nifla
let lines = []
attempt {
    let saved = readfile("ledger.txt")
    if saved != "" {
        lines = split(saved, "\n")
    }
} if it fails {
    say "A brand-new ledger."
}
say "Lines in the book: " + length(lines)
```

```expected
A brand-new ledger.
Lines in the book: 0
```

The book now survives its own absence. In Lesson 11
this little pattern grows into the full loading of the
ledger — gifts, numbers and all.

### Your turn

The program below is broken in two places: one name is
misspelled, and one sum can never be run. It is shown,
not run:

```text
let mesage = "Shalom"
say message
say 10 / 0
```

Fix both faults and make the program run clean.

#### The worked answer

```nifla
let message = "Shalom"
say message
say 10 / 2
```

```expected
Shalom
5
```

### You can now…

- catch a problem that arises along the way with
  `attempt … if it fails`, and hear its own words in
  `problem`;
- tell the two tenses apart: proven ahead of time by
  the checker, or caught as it happens by `attempt`;
- speak to the error stream with `sayerr`, keeping the
  ordinary output clean;
- read a refusal slowly and trust it: the line, the
  problem, the fix.

---

## Lesson 8 — Standing on its own

### Step 1: compiling

So far, `nifla` has run every program: it checks the
program, then interprets it, line by line, itself.
That is the kindest way to learn — but a program you
want to *hand to someone* should stand on its own.
That is `niflac`'s work: it checks the program the
same way, then compiles it into a program of its own,
which runs with no interpreter beside it:

```text
./niflac greeter.nifla -o greeter
./greeter Ada Byron
```

Compiled programs behave exactly as interpreted ones —
same words, same refusals, same output — because the
checker and the meaning are shared. (This book's proof
holds every example to that: each is run both ways,
and the outputs must agree.)

Feel what just happened, because it is the second half
of the promise this book made in its opening. The
*words* did not change — not one letter. What changed
is what stands underneath them: the interpreter stepped
aside, and the program now stands on its own, checked
ahead of time and built to run at full strength.
Written like JavaScript; running like Swift. Same
language, both halves — and you have now held each one.

### Step 2: the words the program was run with

A program that stands on its own usually wants to know
what it was run *with*. `arguments()` gives the list
of words that came after the program's name on the
command line. You have been using it since Lesson 6;
here is its close-up:

```nifla
let args = arguments()
say "You brought " + length(args) + " word(s)."
say "First: " + args[0]
say join(args, " and ")
```

```expected
You brought 2 word(s).
First: Ada
Ada and Byron
```

This book's proof runs every example with the
arguments `Ada` and `Byron`, which is why this program
greets them. On your machine, run your own copy with
your own name and see it greet you instead.

**Your turn.** Say the *second* word you were run
with, with "Second: " in front of it.

#### The worked answer

```nifla
let args = arguments()
say "Second: " + args[1]
```

```expected
Second: Byron
```

### Step 3: how a program ends

A standalone program also reports *how it ended*. When
a program simply finishes, it hands back the number 0
— the number for "all went well". `exitwith(code)`
ends a program early, handing back a number of your
choosing; any number but 0 says something didn't go as
hoped, and whoever ran your program can ask for the
number and act on it:

```nifla exit=3
say "Starting"
exitwith(3)
say "Never reached"
```

```expected
Starting
```

The second `say` is never reached, and the 3 travels
back to whoever ran the program. Lesson 9's doorman
uses exactly this honesty: `feathercheck` answers 0
for a true card and 1 for a false one, so a script can
ask "was it true?" without reading a word.

**Your turn.** Say "Opening the gate.", end with
`exitwith(2)`, and put a `say` after it that will
never be reached.

#### The worked answer

```nifla exit=2
say "Opening the gate."
exitwith(2)
say "Never reached"
```

```expected
Opening the gate.
```

### The ledger grows: the book, compiled

The ledger is ready to stand on its own. The whole
book so far — gifts, tools, total — compiled once and
run like any other program. And because a standalone
program can be handed words, the book can greet its
keeper:

```nifla
make addgift(gifts, who, cents) {
    append(gifts, { who: who, cents: cents })
}
make total(gifts) {
    let sum = 0
    for gift in gifts {
        sum = sum + gift.cents
    }
    give sum
}
let gifts = []
addgift(gifts, "Feeding America", 620)
addgift(gifts, "Barry Cunningham", 500)
say arguments()[0] + " keeps this book."
say "Total: " + total(gifts) + " cents"
```

```expected
Ada keeps this book.
Total: 1120 cents
```

On your machine you would compile it once —

```text
./niflac ledger.nifla -o ledger
./ledger Tyler
```

— and it would answer "Tyler keeps this book." The
proof runs it with Ada, as everywhere in this book.

### Your turn

Write a program that says the words it was run with,
joined with " + ", and then — if it was brought fewer
than 2 words — ends early with `exitwith(1)`.
Otherwise it says "Enough words." (This book's proof
brings two words, so you will see the second road.)

#### The worked answer

```nifla
let args = arguments()
say join(args, " + ")
if length(args) < 2 {
    exitwith(1)
}
say "Enough words."
```

```expected
Ada + Byron
Enough words.
```

### You can now…

- compile a program with `niflac` so it stands on its
  own, behaving exactly as it did interpreted;
- read the words a program was run with, through
  `arguments()`;
- end a program early with `exitwith`, and say how it
  ended in a number — 0 for "all went well".

---

## Lesson 9 — Your first feather

### Step 1: a program that visits

Every program so far has owned its machine: it starts,
it runs, it ends. A *guest* program is different. It is
built to be laid inside another program — a *host* —
which hands it one number, lets it run, and receives a
parting number back. The guest does not boot and does
not stop the machine; it *visits*.

A guest is written in the bare subset of Nifla (the
next lesson looks downstairs properly; for now, know
that on bare metal the language is sterner and
smaller), and it uses two small tools of its own:
`guestvalue()` reads the number the host handed in,
and `guestgive(n)` leaves the parting number:

```nifla-bare-guest
let gift = guestvalue()
say "A feather is visiting."
say "The host sent " + gift
guestgive(gift + 1)
```

That program is not run by this book's proof — it is
*compiled*, with the flags the next step shows, and it
runs when a host calls it through its door. Its `say`
lines speak on the host's screen, in the host's house,
as a guest should.

### Step 2: the card

A guest by itself is just a program. A *feather* is a
guest together with its *card*, made by the compiler
in one step:

```text
./niflac --bare --guest --feather visitor.nifla -o visitor.feather
```

The card stands at the feather's head, in plain text —
the program's name, what it needs, how many bytes the
program is, and a checksum of those bytes (a
reckoning called FNV-1a-64, which any different byte
anywhere changes). Here is a real card, from a real
build of the program in Step 1:

```text
CARDNULL FEATHER 1
name: visitor
needs: the guest door (desk version 1)
bytes: 1732
checksum: 2ce37ea9666eea2e
```

A host's *door* is the part of the host that receives
feathers. The door reads the card, reckons the
checksum over the program bytes that follow it, and
lets the feather in only when card and program agree —
laying it at the *doorstep*, a fixed address (2 MiB)
the guest was linked for, and calling it there. The
honesty of it, stated once and plainly: the checksum
proves the bytes match the card and nothing more — it
is a card, not a signature — and there is no isolation:
host and guest share one memory, and a faulting guest
stops the whole machine. A feather is a trusted
visitor, checked at the door, not a prisoner in a
cell.

### Step 3: the doorman's test

Anyone can run the door's test before any door is
involved. `feathercheck` reads a feather and answers
in plain words whether its card is true — and answers
with its exit code too (Lesson 8): 0 for true, 1 for
not true. On the feather built above:

```text
./feathercheck visitor.feather
```

```text
Feather: visitor
Needs: the guest door (desk version 1)
The card says the program is 1732 bytes, with checksum 2ce37ea9666eea2e.
The program as it stands is 1732 bytes, with checksum 2ce37ea9666eea2e.
The card is true: the program is whole, and a door may let this feather in.
```

**Your turn.** In your own copy of the feather file,
change one byte anywhere in the program part — a hex
editor will do it, or flip a letter well past the
card — and run `feathercheck` again. Before you run
it, say out loud what you expect: which line will
change, and which will not?

#### The worked answer

The name and needs lines stand unchanged — the card is
untouched. The reckoned line changes, because the
program no longer matches its card, and the verdict
turns:

```text
Feather: visitor
Needs: the guest door (desk version 1)
The card says the program is 1732 bytes, with checksum 2ce37ea9666eea2e.
The program as it stands is 1732 bytes, with checksum 7496d3f0a6fbd8b9.
The card is not true: the program does not match its card, so a door must refuse this feather.
```

(Your reckoned checksum will differ from this one —
it depends on which byte you changed. The shape of the
answer will not differ.)

### The living example

This is not a toy mechanism. Cardnull OS 2 — an
operating system written in Nifla — opens with a
welcome feather that visits through exactly this door.
Its card, as the Primer records it:

```text
CARDNULL FEATHER 1
name: welcome-feather
needs: the guest door (desk version 1)
bytes: 2656
checksum: 0b2452a707571de8
```

The feather you just made is the welcome feather's
younger sibling: same card, same door, same test.

Sit with that a moment. A few lessons ago you compiled
a greeter and thought it a big step. Now you have
built, card and all, the same kind of program an
operating system opens its door to — in the same
language, with the same words you started with.

### Your turn

Write a feather of your own: a guest that is handed a
number and gives back three times it. (It will be
compiled with `--bare --guest` by the proof, as every
guest in this book is.)

#### The worked answer

```nifla-bare-guest
let gift = guestvalue()
guestgive(gift * 3)
```

### You can now…

- say what a guest is: a program that visits a host,
  handed one number and leaving one number;
- make a feather with `niflac --bare --guest
  --feather` — a guest with its card laid on it;
- read a card: name, needs, byte count, checksum;
- test any feather with `feathercheck`, and read its
  plain-words verdict, true or not true.

---

## Lesson 10 — A first look downstairs

### Step 1: why there is a downstairs

Everything you have written so far lives on the
friendly side of the language: values are managed,
every access is checked, loops and calls are guarded.
That is deliberate — Nifla's stated bar is memory
safety in the way Swift is memory-safe, and the
friendly side keeps it.

But some programs must touch the machine itself: an
operating system has no operating system beneath it.
For them, the language keeps a *floor* — a deliberate,
marked door out of the safety. A floor block holds raw
processor instructions (x86-64, written the Intel
way), which the compiler lays into the program
untouched and unchecked. Inside a floor block you can
touch any memory the program may touch — including
memory that isn't yours, which is exactly why the
floor is a door and not the house. Floor code runs
only in *compiled* programs: the interpreter refuses
any program that holds floor code, before anything
runs, in plain words.

A floor block is handed a *desk*, and hands answers
back on it. The numbers it is handed wait in an array
pointed to by the register **r10** — the first at
`[r10]`, the second at `[r10 + 8]` — and **r11** says
how many there are. The block's main answer is left in
**rax**:

```nifla-floor
let plus = floor(41) {
    mov rax, [r10]
    add rax, 1
}
say plus
```

```expected
42
```

Read it as: take the first handed number (41), add 1,
leave the answer in `rax` — and the floor block, as a
whole, *is* that answer, kept here on the shelf `plus`.

**Your turn.** Write a floor block that takes the
first handed number and doubles it: hand it 21 and
say the answer.

#### The worked answer

```nifla-floor
let doubled = floor(21) {
    mov rax, [r10]
    add rax, rax
}
say doubled
```

```expected
42
```

### Step 2: two answers at once

Extra answers may be written into a results area at
**r13**, with **r14** saying how many — and then the
block gives back a list of them all. Division is the
classic case: a quotient *and* a remainder:

```nifla-floor
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
[14, 2]
16
```

The desk's *meaning* — handed numbers, one text or
bytes, a main answer and extra answers — is the
contract on every machine the language targets; the
register letters are each target's own. The Primer's
Part 4 keeps the whole desk, and Part 5 names the
second target's letters.

### Step 3: bare metal, briefly and honestly

Below the floor is the basement itself: *bare metal*.
`niflac --bare` compiles a program into a binary that
boots on its own — no operating system, no runtime.
The bare subset is sterner than the hosted language,
and the compiler refuses whatever it cannot honestly
hold, in plain words: whole numbers only, no lists and
no objects, no `nothing` and no `maybe` — every value
there is a machine word with one shape. In exchange, a
bare program gets the machine's own furniture: the
tick count, the keyboard, the memory map, the disk —
and `say` writes to the machine's text screen. This
is a look, not a lesson; the Primer's Part 5 and the
README teach it properly. One taste, compiled by this
book's proof and run when the language's bare suites
boot its kind:

```nifla-bare
let t = ticks()
waittick()
if ticks() > t {
    say "Time passed"
}
```

Cardnull OS 2 is built down there — a whole operating
system standing on the bare subset, its feathers
visiting through Lesson 9's door. You have now seen
every floor of the house you have been learning in.

That deserves a pause. The operating system is not
written in some bigger language that Nifla imitates.
It is written in *Nifla* — the language of your first
lesson, of `say` and `let` and `make`. The subset down
here is sterner because the ground is bare, but the
words are the same words, all the way from hello world
to the booting of a machine.

### Your turn

A floor block that takes two numbers and gives back
the first minus the second. Hand it 50 and 8; the
answer should be 42.

#### The worked answer

```nifla-floor
let difference = floor(50, 8) {
    mov rax, [r10]
    sub rax, [r10 + 8]
}
say difference
```

```expected
42
```

### You can now…

- say what the floor is: a marked door out of the
  language's safety, holding raw processor
  instructions, compiled programs only;
- read a floor block's desk: handed numbers at `r10`,
  the count at `r11`, the main answer in `rax`, extra
  answers at `r13`/`r14`;
- say what bare metal is — a program that boots with
  nothing beneath it — and why its subset is sterner.

---

## Lesson 11 — Capstone: the giving ledger, whole

You have been building this book since Lesson 1 — one
gift said out loud, then a total, then gifts with
names, then tools, then finding, then papers. One
trick remains, and then the book can be assembled
entire.

### Step 1: reading numbers back

The loose end from Lesson 6: a file holds text, so
the cents in `Feeding America|620` come back as the
characters "620", not the number. But you own every
tool needed to teach a program to read digits: `part`
takes one character at a time, and `find` in the text
"0123456789" turns a character into its value — "6"
sits at place 6. Walk the characters, and build the
number the way you would read it aloud: each new digit
moves the value one place over (× 10) and adds in:

```nifla
make digits(text) -> number {
    let value = 0
    let i = 0
    while i < length(text) {
        let d = find("0123456789", part(text, i, 1))
        value = value * 10 + d
        i = i + 1
    }
    give value
}
say digits("620")
say digits("10000")
```

```expected
620
10000
```

Nothing new was needed — a loop from Lesson 2, two
tools from Lesson 3, a function from Lesson 4. That is
what a capstone is for: discovering that the pieces
you already own compose into the thing you thought
you couldn't do.

**Your turn.** Use `digits` to read "500" and say it
with 5 added — the answer must be the number 505, not
the text "5005".

#### The worked answer

```nifla
make digits(text) -> number {
    let value = 0
    let i = 0
    while i < length(text) {
        let d = find("0123456789", part(text, i, 1))
        value = value * 10 + d
        i = i + 1
    }
    give value
}
say digits("500") + 5
```

```expected
505
```

### Step 2: the book loads and saves itself

Now the ledger's papers become a true round trip. Two
tools carry it: `loadgifts` reads `ledger.txt` if it
is there — splitting it into lines, splitting each
line at its bar, reading the cents back with `digits`
— and starts empty, kindly, if it is not.
`savegifts` writes the book back in the same shape:

```nifla
make digits(text) -> number {
    let value = 0
    let i = 0
    while i < length(text) {
        let d = find("0123456789", part(text, i, 1))
        value = value * 10 + d
        i = i + 1
    }
    give value
}
make loadgifts() {
    let gifts = []
    attempt {
        let saved = readfile("ledger.txt")
        if saved != "" {
            let lines = split(saved, "\n")
            for line in lines {
                let fields = split(line, "|")
                append(gifts, { who: fields[0], cents: digits(fields[1]) })
            }
        }
    } if it fails {
        say "A brand-new ledger."
    }
    give gifts
}
make savegifts(gifts) {
    let lines = []
    for gift in gifts {
        append(lines, gift.who + "|" + gift.cents)
    }
    writefile("ledger.txt", join(lines, "\n"))
}
let gifts = loadgifts()
append(gifts, { who: "Feeding America", cents: 620 })
savegifts(gifts)
for gift in gifts {
    say gift.who + ": " + gift.cents + " cents"
}
```

```expected
A brand-new ledger.
Feeding America: 620 cents
```

Run it twice on your machine. The second run says no
"A brand-new ledger." — the book was there, it loaded,
and now it holds *two* gifts to Feeding America. The
book remembers. That small disappearance of one line
is the whole of Lesson 6, paying off.

### Step 3: the whole book

Everything, assembled. The tools from Lessons 4, 5,
and 11; the papers from Lesson 6; the kindness of
Lesson 7; ready to be compiled by Lesson 8 into a
program that stands on its own. On its first run the
book seeds itself with two opening gifts; on every
later run it simply opens where it left off:

```nifla
make digits(text) -> number {
    let value = 0
    let i = 0
    while i < length(text) {
        let d = find("0123456789", part(text, i, 1))
        value = value * 10 + d
        i = i + 1
    }
    give value
}
make loadgifts() {
    let gifts = []
    attempt {
        let saved = readfile("ledger.txt")
        if saved != "" {
            let lines = split(saved, "\n")
            for line in lines {
                let fields = split(line, "|")
                append(gifts, { who: fields[0], cents: digits(fields[1]) })
            }
        }
    } if it fails {
        say "A brand-new ledger."
    }
    give gifts
}
make savegifts(gifts) {
    let lines = []
    for gift in gifts {
        append(lines, gift.who + "|" + gift.cents)
    }
    writefile("ledger.txt", join(lines, "\n"))
}
make addgift(gifts, who, cents) {
    append(gifts, { who: who, cents: cents })
}
make total(gifts) {
    let sum = 0
    for gift in gifts {
        sum = sum + gift.cents
    }
    give sum
}
make findgift(gifts, who) -> maybe object {
    for gift in gifts {
        if gift.who == who {
            give gift
        }
    }
}
let gifts = loadgifts()
if length(gifts) == 0 {
    addgift(gifts, "Feeding America", 620)
    addgift(gifts, "Barry Cunningham", 500)
    savegifts(gifts)
}
let found = findgift(gifts, "Barry Cunningham")
if found == nothing {
    say "No gift to Barry Cunningham is in the book."
} else {
    say "Barry Cunningham: " + found.cents + " cents"
}
let missing = findgift(gifts, "Noki")
if missing == nothing {
    say "No gift to Noki is in the book."
}
for gift in gifts {
    say gift.who + ": " + gift.cents + " cents"
}
say "Total: " + total(gifts) + " cents"
```

```expected
A brand-new ledger.
Barry Cunningham: 500 cents
No gift to Noki is in the book.
Feeding America: 620 cents
Barry Cunningham: 500 cents
Total: 1120 cents
```

Read it once, top to bottom, slowly. There is nothing
in it you did not learn in a small step, and nothing
in it you could not now change with confidence: a new
kind of report, a new question for the book to answer,
a kinder message. That is the test of a course — not
that you can repeat its programs, but that the
programs have become *yours*.

Compile it, as Lesson 8 taught, and it stands on its
own:

```text
./niflac ledger.nifla -o ledger
./ledger
```

### Your turn

The book is yours now. In the final program, add one
more opening gift — "Mother of Mercy", 250 cents — to
the seeding (and save the book after seeding, as the
program already does). Before you run it, say what
the new total will be. Then run it and see.

#### The worked answer

The new total is 1120 + 250 = **1370 cents**, reckoned
before running — and the program agrees:

```nifla
make digits(text) -> number {
    let value = 0
    let i = 0
    while i < length(text) {
        let d = find("0123456789", part(text, i, 1))
        value = value * 10 + d
        i = i + 1
    }
    give value
}
make loadgifts() {
    let gifts = []
    attempt {
        let saved = readfile("ledger.txt")
        if saved != "" {
            let lines = split(saved, "\n")
            for line in lines {
                let fields = split(line, "|")
                append(gifts, { who: fields[0], cents: digits(fields[1]) })
            }
        }
    } if it fails {
        say "A brand-new ledger."
    }
    give gifts
}
make savegifts(gifts) {
    let lines = []
    for gift in gifts {
        append(lines, gift.who + "|" + gift.cents)
    }
    writefile("ledger.txt", join(lines, "\n"))
}
make addgift(gifts, who, cents) {
    append(gifts, { who: who, cents: cents })
}
make total(gifts) {
    let sum = 0
    for gift in gifts {
        sum = sum + gift.cents
    }
    give sum
}
make findgift(gifts, who) -> maybe object {
    for gift in gifts {
        if gift.who == who {
            give gift
        }
    }
}
let gifts = loadgifts()
if length(gifts) == 0 {
    addgift(gifts, "Feeding America", 620)
    addgift(gifts, "Barry Cunningham", 500)
    addgift(gifts, "Mother of Mercy", 250)
    savegifts(gifts)
}
let found = findgift(gifts, "Barry Cunningham")
if found == nothing {
    say "No gift to Barry Cunningham is in the book."
} else {
    say "Barry Cunningham: " + found.cents + " cents"
}
let missing = findgift(gifts, "Noki")
if missing == nothing {
    say "No gift to Noki is in the book."
}
for gift in gifts {
    say gift.who + ": " + gift.cents + " cents"
}
say "Total: " + total(gifts) + " cents"
```

```expected
A brand-new ledger.
Barry Cunningham: 500 cents
No gift to Noki is in the book.
Feeding America: 620 cents
Barry Cunningham: 500 cents
Mother of Mercy: 250 cents
Total: 1370 cents
```

### You can now…

- read numbers out of text with a `digits` tool built
  from `part` and `find`;
- load and save a whole book of records as text lines,
  round trip, surviving between runs;
- assemble everything — keeping, deciding, repeating,
  lists, objects, tools, kinds, nothing, papers,
  attempts — into one real program, and compile it to
  stand on its own.

---

## Where to go next

You have walked the whole path once. The shelf is
still there when you need it: `PRIMER.md` keeps every
word and tool of the language, one at a time, and the
README in this repository is the language's full
record — every stone of its building, in order, with
the honest limits named. The suites (`examples/`,
`checker-examples/`, `floor-examples/`,
`bare-examples/`) are hundreds of small true programs
to read and borrow from.

Build something small that is yours: a garden log, a
verse keeper, a book of your own keeping. Keep it
exact, keep it kind, and when the checker stops you at
the door, read its words slowly — it is on your side.

And the promise from the opening, kept: you wrote like
JavaScript the whole way — type, run, read — and your
words ran with Swift's strength — checked, compiled,
standing on their own. And the language you now hold
is an operating system's language. Whatever you build
next with it, you are building in the real thing.

Welcome to Nifla.
