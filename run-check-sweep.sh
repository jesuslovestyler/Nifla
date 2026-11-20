#!/bin/sh
# Stone 52 proof: identity, proved whole — the generated
# sweep for the checker.
#
# Stones 50 and 51 proved the Nifla-written checker
# (selfhost/nifla-front.nifla's check, check-bare and
# check-guest modes) identical to the Swift checker
# (src/Checker.swift, through the proof-only oracle
# tools/check-oracle.swift) across the whole hand-written
# corpus and the 64 fixtures in check-examples/. This
# sweep adds generated cases no one hand-picked: a seeded
# generator (python's random.Random with fixed seeds, so
# the same cases are made on every run and any failure
# reproduces exactly) writes three families of scratch
# files, and every file is run through both checkers —
# stdout, stderr and exit code compared byte for byte,
# every run wrapped in `timeout 30`:
#
#   verdicts (300 cases, check mode): complete programs
#     from a seeded grammar aimed at checker verdicts —
#     typed and untyped lets, binary operations over
#     kind-known and kind-unknown operands, calls to made
#     functions and built-in tools (right and wrong
#     counts, kinds and proven ranges), annotations on
#     let/assign/give, maybe-typed values used raw and
#     narrowed, if/while merges, function bodies using
#     outer and nowhere names, and floor blocks. Each
#     case is built to aim at acceptance or at refusal,
#     so the family mixes both; the summary counts the
#     split the oracle actually gave.
#   door     (200 cases, check-bare AND check-guest):
#     small programs calling bare, guest, built-in, made
#     and unknown names with 0–3 arguments of mixed
#     kinds, so crossings, arities and unknown names are
#     compared in the two modes where they differ. Each
#     case runs in both modes and each mode is counted.
#   numbers  (250 cases, check mode): programs whose
#     verdict turns on tracked constants and lengths —
#     literal-initialized variables and arithmetic over
#     them feeding divisors, repeat counts, indices,
#     part spans, makebytes counts and exitwith codes,
#     with values chosen near the boundaries where the
#     verdict flips, so constNumber / literalLength
#     fidelity decides.
#
# Prints per-family counts (with the oracle's
# accept/refuse split) and PASS or FAIL.

set -u
cd "$(dirname "$0")"

./build.sh >/dev/null || { echo "FAIL: build.sh failed"; exit 1; }

# Find swiftc the way build.sh does.
SWIFTC="${SWIFTC:-}"
if [ -z "$SWIFTC" ]; then
    if command -v swiftc >/dev/null 2>&1; then
        SWIFTC="$(command -v swiftc)"
    elif [ -x /opt/swift/usr/bin/swiftc ]; then
        SWIFTC=/opt/swift/usr/bin/swiftc
    elif [ -x "$HOME/swift/usr/bin/swiftc" ]; then
        SWIFTC="$HOME/swift/usr/bin/swiftc"
    elif [ -x "$HOME/workspace/turtle-browser/harness-038/toolchain/swift-6.0.3-RELEASE-ubuntu24.04/usr/bin/swiftc" ]; then
        SWIFTC="$HOME/workspace/turtle-browser/harness-038/toolchain/swift-6.0.3-RELEASE-ubuntu24.04/usr/bin/swiftc"
    else
        echo "FAIL: no swiftc found (set SWIFTC=/path/to/swiftc)"
        exit 1
    fi
fi

SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT

echo "Building the oracle (untouched src/Lexer.swift + src/Parser.swift + src/Interpreter.swift + src/BareCompiler.swift + src/Checker.swift + src/Compiler.swift + src/BareCompilerARM.swift + tools/check-oracle.swift)..."
"$SWIFTC" src/Lexer.swift src/Parser.swift src/Interpreter.swift src/BareCompiler.swift src/Checker.swift src/Compiler.swift src/BareCompilerARM.swift tools/check-oracle.swift -o "$SCRATCH/check-oracle" || { echo "FAIL: the oracle did not build"; exit 1; }

echo "Compiling the front end (selfhost/nifla-front.nifla) with niflac..."
if ! timeout 600 ./niflac selfhost/nifla-front.nifla -o "$SCRATCH/nifla-front" > "$SCRATCH/front-build.log" 2>&1; then
    echo "FAIL: niflac could not compile the front end:"
    cat "$SCRATCH/front-build.log"
    exit 1
fi

ORACLE="$SCRATCH/check-oracle"
FRONT="$SCRATCH/nifla-front"

# Generate the cases. Fixed seeds: the same files on every
# run, so a failure reproduces exactly from its family and
# index (the file names carry both).
python3 - "$SCRATCH" <<'PYEOF'
import os
import random
import sys

scratch = sys.argv[1]

# ---------- shared helpers ----------

class Gen:
    def __init__(self, rng):
        self.rng = rng
        self.n = 0

    def fresh(self, stem="v"):
        self.n += 1
        return f"{stem}{self.n}"

    def num(self, lo=0, hi=20):
        return str(self.rng.randint(lo, hi))

    def text(self):
        return '"' + self.rng.choice(
            ["hi", "hello", "abc", "Tyler", "a b", "x", "shalom", ""]) + '"'

# ---------- verdict snippets ----------
# Each snippet is a self-contained group of lines using
# fresh names only. OK snippets are accepted on their own;
# BAD snippets earn a refusal on their own.

def ok_typed_let(g):
    v = g.fresh()
    kind, val = g.rng.choice([
        ("number", g.num()), ("text", g.text()),
        ("boolean", "true"), ("boolean", "false")])
    return [f"let {v}: {kind} = {val}", f"say {v}"]

def ok_untyped_binary(g):
    v = g.fresh()
    a, b = g.num(1, 50), g.num(1, 50)
    op = g.rng.choice(["+", "-", "*", "/"])
    return [f"let {v} = {a}", f"say {v} {op} {b}"]

def ok_text_binary(g):
    v = g.fresh()
    return [f"let {v} = {g.text()}", f"say {v} + {g.text()}",
            f"say {v} == {g.text()}"]

def ok_unknown_param(g):
    f = g.fresh("fn")
    p = g.fresh("p")
    return [f"make {f}({p}) {{", f"    say {p} + 1",
            f"    give {p}", "}", f"say {f}({g.num()})"]

def ok_made_call(g):
    f = g.fresh("fn")
    lines = [f"make {f}(a: number, b: text) -> number {{",
             "    give a", "}",
             f"say {f}({g.num()}, {g.text()})"]
    return lines

def ok_builtin(g):
    v = g.fresh()
    return [g.rng.choice([
        f"let {v} = length({g.text()})",
        f"let {v} = length([1, 2, 3])",
        f"let {v} = part(\"hello world\", 0, 5)",
        f"let {v} = find(\"hello\", \"ell\")",
        f"let {v} = join([\"a\", \"b\"], \" \")",
        f"let {v} = split(\"a,b,c\", \",\")",
        f"let {v} = asnumber(\"42\")",
        f"let {v} = wholediv(17, 5)",
        f"let {v} = leftover(17, 5)",
        f"let {v} = absolute(0 - 7)",
        f"let {v} = smallest(3, 7)",
        f"let {v} = makebytes(8)",
        f"let {v} = sorted([3, 1, 2])",
        f"let {v} = arguments()",
    ]), f"say {v}"]

def ok_annotation_assign(g):
    v = g.fresh()
    return [f"let {v}: number = 1", f"{v} = {g.num()}", f"say {v}"]

def ok_annotation_give(g):
    f = g.fresh("fn")
    return [f"make {f}() -> text {{", f"    give {g.text()}", "}",
            f"say {f}()"]

def ok_maybe_annotated(g):
    v = g.fresh()
    return [f"let {v}: maybe number = nothing", f"say {v}"]

def ok_maybe_narrow_if(g):
    f = g.fresh("fn")
    v = g.fresh()
    return [f"make {f}() -> maybe number {{", "    give 7", "}",
            f"let {v} = {f}()",
            f"if {v} == nothing {{", "    say \"none\"",
            "} else {", f"    say {v} + 1", "}"]

def ok_maybe_narrow_ne(g):
    f = g.fresh("fn")
    v = g.fresh()
    return [f"make {f}() -> maybe number {{", "    give 7", "}",
            f"let {v} = {f}()",
            f"if {v} != nothing {{", f"    say {v} * 2",
            "} else {", "    say \"none\"", "}"]

def ok_maybe_narrow_while(g):
    f = g.fresh("fn")
    v = g.fresh()
    return [f"make {f}() -> maybe number {{", "    give 7", "}",
            f"let {v} = {f}()",
            f"while {v} != nothing {{", f"    say {v} + 1",
            f"    {v} = nothing", "}"]

def ok_merge_unknown(g):
    v = g.fresh()
    return [f"let {v} = 1", "if 1 < 2 {", f"    {v} = {g.text()}", "}",
            f"say {v} - 1"]

def ok_merge_narrow(g):
    v = g.fresh()
    return [f"let {v} = 1", "if 1 < 2 {", f"    {v} = nothing", "}",
            f"if {v} == nothing {{", "    say \"none\"",
            "} else {", f"    say {v} + 1", "}"]

def ok_outer_forgiven(g):
    f = g.fresh("fn")
    v = g.fresh()
    return [f"make {f}() {{", f"    give {v}", "}",
            f"let {v} = 42", f"say {f}()"]

def ok_floor_number(g):
    v = g.fresh()
    return [f"let {v} = floor({g.num(1, 9)}) {{",
            "    mov rax, 1", "}", f"say {v}"]

def ok_floor_bytes(g):
    v = g.fresh()
    return [f"let {v} = floor(makebytes(4)) {{",
            "    mov rax, 1", "}", f"say {v}"]

def ok_floor_statement_asm(g):
    return ["floor {", "    nop", "    mov rcx, 7", "}"]

def ok_repeat_divisor(g):
    v = g.fresh()
    d = g.fresh()
    return [f"let {d} = {g.num(2, 9)}", f"say 100 / {d}",
            f"repeat {d} {{", "    say \"x\"", "}"]

def ok_index(g):
    v = g.fresh()
    return [f"let {v} = [10, 20, 30]", f"say {v}[{g.num(0, 2)}]",
            "say \"hello\"[1]"]

def ok_object_field(g):
    v = g.fresh()
    return [f"let {v} = {{name: {g.text()}, score: {g.num()}}}",
            f"say {v}.name", f"say {v}.score + 1"]

def ok_for_list(g):
    it = g.fresh("it")
    return [f"for {it} in [1, 2, 3] {{", f"    say {it}", "}"]

def ok_attempt(g):
    v = g.fresh()
    return [f"let {v} = {g.num()}",
            "attempt {", f"    say {v} + 1",
            "} if it fails {", "    say \"caught\"", "}"]

OK_SNIPPETS = [ok_typed_let, ok_untyped_binary, ok_text_binary,
               ok_unknown_param, ok_made_call, ok_builtin,
               ok_annotation_assign, ok_annotation_give,
               ok_maybe_annotated, ok_maybe_narrow_if,
               ok_maybe_narrow_ne, ok_maybe_narrow_while,
               ok_merge_unknown, ok_merge_narrow, ok_outer_forgiven,
               ok_floor_number, ok_floor_bytes, ok_floor_statement_asm,
               ok_repeat_divisor, ok_index, ok_object_field,
               ok_for_list, ok_attempt]

def bad_typed_let(g):
    v = g.fresh()
    kind, val = g.rng.choice([
        ("number", g.text()), ("text", g.num()),
        ("boolean", g.num()), ("number", "true"),
        ("text", "[1, 2]"), ("nothing", "5")])
    return [f"let {v}: {kind} = {val}", f"say {v}"]

def bad_binary(g):
    v = g.fresh()
    return [g.rng.choice([
        f"say {g.text()} - {g.num()}",
        f"say {g.num()} * {g.text()}",
        f"say {g.text()} / {g.num()}",
        f"say true + {g.num()}",
        f"say {g.text()} < {g.num()}",
    ])]

def bad_made_count(g):
    f = g.fresh("fn")
    call = g.rng.choice([f"{f}()", f"{f}(1)", f"{f}(1, \"x\", 3)"])
    return [f"make {f}(a: number, b: text) -> number {{",
            "    give a", "}", f"say {call}"]

def bad_made_kind(g):
    f = g.fresh("fn")
    call = g.rng.choice([f"{f}(\"x\", \"y\")", f"{f}(1, 2)",
                         f"{f}(true, \"y\")"])
    return [f"make {f}(a: number, b: text) -> number {{",
            "    give a", "}", f"say {call}"]

def bad_builtin(g):
    return [g.rng.choice([
        "say length(5)",
        "say length(\"a\", \"b\")",
        "say join(\"a\", \" \")",
        "say join([\"a\"])",
        "say split(5, \",\")",
        "say part(5, 0, 1)",
        "say part(\"hello\", -1, 2)",
        "say part(\"hello\", 0, 99)",
        "say part(\"hello\", 9, 1)",
        "say find(\"abc\", 5)",
        "say append(5, 1)",
        "say readfile(5)",
        "say makebytes(-3)",
        "say makebytes(20000000)",
        "say makebytes(\"x\")",
        "exitwith(300)",
        "exitwith(2.5)",
        "say removeat([1, 2], 5)",
        "say removeat([], 0)",
        "say removeat(\"x\", 0)",
        "say insertat([1], \"x\", 2)",
        "say sorted(5)",
        "say fieldnames([1])",
        "say asnumber(5)",
        "say astext(\"hi\")",
        "say wholediv(10, 0)",
        "say wholediv(\"a\", 2)",
        "say leftover(10, 0)",
        "say bitand(1, \"a\")",
        "say rounddown(\"a\")",
        "say smallest(1, \"a\")",
        "say arguments(1)",
        "sayerr()",
        "say 10 / 0",
        "say -\"hi\"",
        "say -nothing",
    ])]

def bad_annotation_assign(g):
    v = g.fresh()
    kind, first, second = g.rng.choice([
        ("number", "1", g.text()), ("text", g.text(), g.num())])
    return [f"let {v}: {kind} = {first}", f"{v} = {second}"]

def bad_annotation_give(g):
    f = g.fresh("fn")
    ret, val = g.rng.choice([("number", g.text()), ("text", "42"),
                             ("boolean", g.num())])
    return [f"make {f}() -> {ret} {{", f"    give {val}", "}",
            f"say {f}()"]

def bad_maybe_raw(g):
    f = g.fresh("fn")
    v = g.fresh()
    use = g.rng.choice([f"say {v} + 1", f"say {v} * 2",
                        f"say length({v})", f"say -{v}"])
    return [f"make {f}() -> maybe number {{", "    give 7", "}",
            f"let {v} = {f}()", use]

def bad_merge_maybe(g):
    v = g.fresh()
    use = g.rng.choice([f"say {v} + 1", f"repeat {v} {{",
                        f"say {v}[0]"])
    lines = [f"let {v} = 1", "if 1 < 2 {", f"    {v} = nothing", "}",
             use]
    if use.startswith("repeat"):
        lines.append("    say \"x\"")
        lines.append("}")
    return lines

def bad_nowhere(g):
    f = g.fresh("fn")
    return g.rng.choice([
        ["say zzzNowhere"],
        ["let q = zzzNowhere", "say q"],
        ["say nosuchfn(1)"],
        ["zzzNowhere = 5"],
        [f"make {f}() {{", "    give zzzNowhere", "}",
         f"say {f}()"],
    ])

def bad_repeat(g):
    return [g.rng.choice([
        "repeat 0 - 3 {", "repeat \"x\" {", "repeat nothing {",
    ]), "    say \"x\"", "}"]

def bad_index(g):
    v = g.fresh()
    return [g.rng.choice([
        "say \"abc\"[true]",
        "say \"abc\"[9]",
        "say [1, 2][5]",
        "say [][0]",
        "say nothing[0]",
        f"let {v} = [1, 2, 3]\nsay {v}[3]",
    ])]

def bad_floor(g):
    v = g.fresh()
    return g.rng.choice([
        ["floor {", "}"],
        [f"let {v} = floor({g.text()}) {{", "    mov rax, 1", "}",
         f"say {v}"],
        [f"let {v} = floor([1, 2]) {{", "    mov rax, 1", "}",
         f"say {v}"],
        ["let a1 = makebytes(2)", "let a2 = makebytes(3)",
         f"let {v} = floor(a1, a2) {{", "    mov rax, 1", "}",
         f"say {v}"],
    ])

def bad_for(g):
    it = g.fresh("it")
    base = g.rng.choice(["nothing", "42", "true"])
    return [f"for {it} in {base} {{", f"    say {it}", "}"]

def bad_field(g):
    return [g.rng.choice([
        "say nothing.name",
        "let z9 = 5\nsay z9.name",
        "say true.name",
    ])]

def bad_divisor_tracked(g):
    d = g.fresh()
    return [f"let {d} = {g.num(0, 4)} - {g.num(0, 4)}",
            f"say 10 / {d}"] if False else [
        f"let {d} = 0", f"say 10 / {d}"]

BAD_SNIPPETS = [bad_typed_let, bad_binary, bad_made_count,
                bad_made_kind, bad_builtin, bad_annotation_assign,
                bad_annotation_give, bad_maybe_raw, bad_merge_maybe,
                bad_nowhere, bad_repeat, bad_index, bad_floor,
                bad_for, bad_field, bad_divisor_tracked]

rng = random.Random(52050)
verdicts_dir = os.path.join(scratch, "verdicts")
os.makedirs(verdicts_dir)
for i in range(1, 301):
    g = Gen(rng)
    lines = [f"// generated verdict case {i} (seed 52050)"]
    if rng.random() < 0.5:
        # Aim at acceptance: only sound snippets.
        for _ in range(rng.randint(3, 5)):
            lines.extend(rng.choice(OK_SNIPPETS)(g))
    else:
        # Aim at refusal: the refusing snippet stands first
        # (the checker speaks its first refusal), with sound
        # snippets after it.
        lines.extend(rng.choice(BAD_SNIPPETS)(g))
        if rng.random() < 0.4:
            lines.extend(rng.choice(BAD_SNIPPETS)(g))
        for _ in range(rng.randint(1, 3)):
            lines.extend(rng.choice(OK_SNIPPETS)(g))
    with open(os.path.join(verdicts_dir, f"verdict-{i:03d}.nifla"), "wb") as f:
        f.write(("\n".join(lines) + "\n").encode("ascii"))

# ---------- door soup ----------

BARE_TOOLS = [("ticks", 0), ("readkey", 0), ("waittick", 0),
              ("memorysize", 0), ("disksectors", 0),
              ("diskread", 2), ("diskwrite", 2)]
GUEST_TOOLS = [("guestvalue", 0), ("guestgive", 1), ("callguest", 2)]
BUILTIN_CALLS = [("length", 1), ("part", 3), ("makebytes", 1),
                 ("exitwith", 1), ("arguments", 0), ("join", 2),
                 ("wholediv", 2), ("asnumber", 1)]
UNKNOWN_NAMES = ["nosuchtool", "tick", "guestvalu", "diskread2",
                 "callgues", "zzzdoor"]
ARG_POOL = ["0", "1", "2", "300", "-1", "2.5", "\"hi\"", "\"\"",
            "true", "false", "nothing", "[1, 2]", "makebytes(2)",
            "5 + 1", "\"a\" + \"b\""]

rng = random.Random(52051)
door_dir = os.path.join(scratch, "door")
os.makedirs(door_dir)
for i in range(1, 201):
    g = Gen(rng)
    lines = [f"// generated door case {i} (seed 52051)"]
    # A made function some cases call.
    made_name = None
    made_nparams = 0
    if rng.random() < 0.5:
        made_name = g.fresh("made")
        nparams = rng.randint(1, 2)
        made_nparams = nparams
        params = ", ".join(f"p{k}" for k in range(nparams))
        lines.append(f"make {made_name}({params}) {{")
        lines.append("    give p0")
        lines.append("}")
    pool = BARE_TOOLS + GUEST_TOOLS + BUILTIN_CALLS + \
        [(name, 0) for name in UNKNOWN_NAMES]
    if made_name is not None:
        pool = pool + [(made_name, 1), (made_name, 2)]
    if rng.random() < 0.40:
        # A single clean call: right name for its mode,
        # right count, kind-sound values — accepted in the
        # mode the name belongs to (and in both modes for
        # built-ins and made functions), refused across
        # the door in the other bare picture.
        clean = ["ticks()", "readkey()", "waittick()",
                 "memorysize()", "disksectors()",
                 "diskread(1, 2)", "diskwrite(1, 2)",
                 "guestvalue()", "guestgive(5)",
                 "callguest(makebytes(2), 1)",
                 "length(\"abc\")", "arguments()",
                 "makebytes(8)", "part(\"hello\", 0, 2)",
                 "wholediv(10, 2)", "asnumber(\"3\")",
                 "join([\"a\"], \" \")"]
        if made_name is not None:
            if made_nparams == 1:
                clean.append(f"{made_name}(1)")
            else:
                clean.append(f"{made_name}(1, 2)")
        call = rng.choice(clean)
        if rng.random() < 0.5:
            lines.append(call)
        else:
            v = g.fresh()
            lines.append(f"let {v} = {call}")
            lines.append(f"say {v}")
        with open(os.path.join(door_dir, f"door-{i:03d}.nifla"), "wb") as f:
            f.write(("\n".join(lines) + "\n").encode("ascii"))
        continue
    for _ in range(rng.randint(1, 3)):
        name, _arity = rng.choice(pool)
        nargs = rng.randint(0, 3)
        args = ", ".join(rng.choice(ARG_POOL) for _ in range(nargs))
        call = f"{name}({args})"
        style = rng.random()
        if style < 0.45:
            lines.append(call)
        elif style < 0.75:
            v = g.fresh()
            lines.append(f"let {v} = {call}")
            lines.append(f"say {v}")
        else:
            lines.append(f"say {call}")
    with open(os.path.join(door_dir, f"door-{i:03d}.nifla"), "wb") as f:
        f.write(("\n".join(lines) + "\n").encode("ascii"))

# ---------- number-heavy verdicts ----------

def arith_expr(rng, base):
    # A constant expression built from small literals whose
    # value stays near `base`'s neighbourhood: plain + - *
    # over literals, sometimes just a tracked variable.
    style = rng.random()
    if style < 0.35:
        return str(base)
    if style < 0.60:
        d = rng.randint(-3, 3)
        if d >= 0:
            return f"{base} + {d}"
        return f"{base} - {-d}"
    if style < 0.80:
        d = rng.randint(-3, 3)
        if d >= 0:
            return f"{base} - {d}"
        return f"{base} + {-d}"
    # A product of two small literals near the value.
    a = rng.randint(0, 4)
    b = rng.randint(0, 4)
    return f"{a} * {b}"

rng = random.Random(52052)
numbers_dir = os.path.join(scratch, "numbers")
os.makedirs(numbers_dir)
for i in range(1, 251):
    g = Gen(rng)
    lines = [f"// generated number case {i} (seed 52052)"]
    scenario = rng.choice(["divisor", "wholediv", "repeat",
                           "index", "textpart", "removeat",
                           "makebytes", "exitwith"])
    if scenario == "divisor":
        d = g.fresh("d")
        base = rng.randint(-1, 3)
        lines.append(f"let {d} = {base}")
        lines.append(f"say 100 / {arith_expr(rng, d)}")
    elif scenario == "wholediv":
        d = g.fresh("d")
        base = rng.randint(-1, 3)
        fn = rng.choice(["wholediv", "leftover"])
        lines.append(f"let {d} = {base}")
        lines.append(f"say {fn}(100, {arith_expr(rng, d)})")
    elif scenario == "repeat":
        c = g.fresh("c")
        base = rng.randint(-3, 4)
        lines.append(f"let {c} = {base}")
        lines.append(f"repeat {arith_expr(rng, c)} {{")
        lines.append("    say \"x\"")
        lines.append("}")
    elif scenario == "index":
        v = g.fresh("items")
        n = rng.randint(0, 5)
        items = ", ".join(str(rng.randint(0, 9)) for _ in range(n))
        idx = g.fresh("idx")
        base = rng.randint(-1, n + 1)
        lines.append(f"let {v} = [{items}]")
        lines.append(f"let {idx} = {base}")
        lines.append(f"say {v}[{arith_expr(rng, idx)}]")
    elif scenario == "textpart":
        t = g.fresh("t")
        text = rng.choice(["", "a", "abc", "hello", "hello world"])
        s = g.fresh("s")
        c = g.fresh("c")
        sbase = rng.randint(-1, len(text) + 1)
        cbase = rng.randint(-1, len(text) + 2)
        lines.append(f"let {t} = \"{text}\"")
        lines.append(f"let {s} = {sbase}")
        lines.append(f"let {c} = {cbase}")
        if rng.random() < 0.5:
            lines.append(f"say part({t}, {arith_expr(rng, s)}, "
                         f"{arith_expr(rng, c)})")
        else:
            lines.append(f"say {t}[{arith_expr(rng, s)}]")
    elif scenario == "removeat":
        v = g.fresh("items")
        n = rng.randint(0, 4)
        items = ", ".join(str(rng.randint(0, 9)) for _ in range(n))
        idx = g.fresh("idx")
        base = rng.randint(-1, n + 1)
        lines.append(f"let {v} = [{items}]")
        lines.append(f"let {idx} = {base}")
        lines.append(f"say removeat({v}, {arith_expr(rng, idx)})")
    elif scenario == "makebytes":
        c = g.fresh("c")
        base = rng.choice([-5, -1, 0, 1, 8, 100,
                           16777215, 16777216, 16777217, 20000000])
        lines.append(f"let {c} = {base}")
        lines.append(f"say length(makebytes({arith_expr(rng, c)}))")
    else:  # exitwith
        c = g.fresh("c")
        base = rng.choice([-1, 0, 1, 42, 254, 255, 256, 300])
        lines.append(f"let {c} = {base}")
        if rng.random() < 0.25:
            lines.append(f"exitwith({c} / 2)")
        else:
            lines.append(f"exitwith({arith_expr(rng, c)})")
    with open(os.path.join(numbers_dir, f"number-{i:03d}.nifla"), "wb") as f:
        f.write(("\n".join(lines) + "\n").encode("ascii"))

print("generated: verdicts 300, door 200, numbers 250 (seeds 52050, 52051, 52052)")
PYEOF
[ $? -eq 0 ] || { echo "FAIL: case generation failed"; exit 1; }

fail=0
SUMMARY=""

# run_family <label> <mode> <dir> — compares the two
# checkers on every generated file in <dir>, and counts
# how many the oracle accepted (exit 0) against how many
# it refused (exit 1), both sides agreeing either way.
run_family() {
    label="$1"
    mode="$2"
    dir="$3"
    fpass=0
    ftotal=0
    accepted=0
    refused=0
    for f in "$dir"/*.nifla; do
        [ -f "$f" ] || continue
        ftotal=$((ftotal + 1))
        timeout 30 "$ORACLE" "$mode" "$f" > "$SCRATCH/o.out" 2> "$SCRATCH/o.err"
        oc=$?
        timeout 30 "$FRONT" "$mode" "$f" > "$SCRATCH/f.out" 2> "$SCRATCH/f.err"
        fc=$?
        if [ "$oc" -eq 0 ]; then
            accepted=$((accepted + 1))
        elif [ "$oc" -eq 1 ]; then
            refused=$((refused + 1))
        fi
        if [ "$oc" -eq "$fc" ] && cmp -s "$SCRATCH/o.out" "$SCRATCH/f.out" && cmp -s "$SCRATCH/o.err" "$SCRATCH/f.err"; then
            fpass=$((fpass + 1))
        else
            echo "FAIL $f mode $mode (oracle exit $oc, front exit $fc)"
            echo "--- stdout diff (oracle vs front):"
            diff "$SCRATCH/o.out" "$SCRATCH/f.out" | head -n 20
            echo "--- stderr diff (oracle vs front):"
            diff "$SCRATCH/o.err" "$SCRATCH/f.err" | head -n 20
            echo "--- case:"
            cat "$f"
            echo "---"
            fail=$((fail + 1))
        fi
    done
    echo "$label: $fpass/$ftotal ($accepted accepted, $refused refused identically)"
    SUMMARY="$SUMMARY $label $fpass/$ftotal ($accepted accepted, $refused refused),"
}

run_family verdicts check "$SCRATCH/verdicts"
run_family door-bare check-bare "$SCRATCH/door"
run_family door-guest check-guest "$SCRATCH/door"
run_family numbers check "$SCRATCH/numbers"

echo "sweep:$SUMMARY"
if [ "$fail" -eq 0 ]; then
    echo "PASS check-sweep (Stone 52: the generated cases — verdicts, door soup in both bare and guest modes, and number-heavy verdicts — agree byte for byte between the Nifla-written checker and the Swift checker)"
else
    echo "FAIL check-sweep: $fail failure(s)"
    exit 1
fi
