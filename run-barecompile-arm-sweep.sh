#!/bin/sh
# Stone 60 proof: the generated sweep for the ARM bare
# compiler — the ARM leg's identity, proved whole.
#
# Stone 59 proved the Nifla-written ARM refusal walk
# and translator (selfhost/nifla-front.nifla's
# barecompile-arm mode) identical to the Swift side
# (armRefusal and BareTranslatorARM in
# src/BareCompilerARM.swift, through the proof-only
# oracle tools/bare-oracle.swift, whose barecompile-arm
# mode drives the real compileBareARM build) across
# the whole hand-written corpus. This sweep adds
# generated cases no one hand-picked: a seeded
# generator (python's random.Random with fixed seeds,
# so the same cases are made on every run and any
# failure reproduces exactly) writes three families of
# scratch files, and every file is run through both
# sides in the barecompile-arm mode — stdout, stderr
# and exit code compared byte for byte, every run
# wrapped in `timeout 30`:
#
#   programs (300 cases): complete programs from a
#     seeded grammar aimed at the bare road's shapes —
#     nested scopes, loops of every kind (the guard
#     tick's counter is exercised hard), text and bytes
#     work, defines with gives, attempts, floor blocks,
#     the guest desk and the host's door — mixed with
#     refused programs (the wrong picture's tools, kind
#     errors, unknown names), whose refusal identity is
#     compared the same way. On this target the desk
#     and door shapes meet the target's own refusal
#     walk as well as the validator's, and the summary
#     counts the split the oracle actually gave.
#   numbers  (200 cases): lets and says whose literals
#     are generated digit strings. The bare law — every
#     number whole and under 1e15 — splits the family:
#     cases built inside the law are accepted and pin
#     the whole-number emission (on this target, the
#     mov/ldr edge at 65535/-65536 among them, wherever
#     the generated values cross it); cases built past
#     it (fractions, the edge itself, wholes too large)
#     are refused, and the refusal speaks the value, so
#     its rendering — the number reader and the number
#     text together — is compared where it can drift.
#     The literals stay inside the reader's proved
#     ground by design, the compile sweep's discipline:
#     fractions no deeper than 22 digits of scale,
#     wholes no longer than 40 digits. Past that ground
#     lies the number boundary, recorded with its
#     fixtures pinned in front-examples/BOUNDARY.txt,
#     where the corpus proofs verify the divergence on
#     every run.
#   texts    (200 cases): lets and says whose text
#     literals are assembled byte by byte from
#     fragments — plain words, the four escapes, text
#     past the ASCII edge (accented letters in both
#     their forms, a combining sequence, CJK, an emoji
#     with a joiner), raw tabs, raw carriage returns
#     (alone, doubled, and standing before the \\n
#     escape), and raw control bytes — so the
#     translator's byte reckoning for literals, the
#     port's subtlest walk, is compared where it can
#     drift: a literal's bytes are counted off the
#     source itself, and two literals may share a line.
#
# There is no cards family: the ARM target lays no
# feather card (compileBareARM writes no card, and
# the command line refuses '--arm --feather'), so the
# card stands proved by Stone 57's sweep alone.
#
# Names stay ASCII in every family by design — word
# characters past Latin-1 are the front end's standing
# boundary, already recorded; values go past ASCII
# deliberately, because values are not the boundary.
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

echo "Building the bare oracle (untouched src/ files + tools/bare-oracle.swift)..."
"$SWIFTC" src/Lexer.swift src/Parser.swift src/Interpreter.swift src/BareCompiler.swift src/Checker.swift src/Compiler.swift src/BareCompilerARM.swift tools/bare-oracle.swift -o "$SCRATCH/bare-oracle" || { echo "FAIL: the oracle did not build"; exit 1; }

echo "Compiling the front end (selfhost/nifla-front.nifla) with niflac..."
if ! timeout 600 ./niflac selfhost/nifla-front.nifla -o "$SCRATCH/nifla-front" > "$SCRATCH/front-build.log" 2>&1; then
    echo "FAIL: niflac could not compile the front end:"
    cat "$SCRATCH/front-build.log"
    exit 1
fi

ORACLE="$SCRATCH/bare-oracle"
FRONT="$SCRATCH/nifla-front"

# Generate the cases. Fixed seeds: the same files on
# every run, so a failure reproduces exactly from its
# family and index (the file names carry both).
python3 - "$SCRATCH" <<'PYEOF'
import os
import random
import sys

scratch = sys.argv[1]

TEXTS = ["hello", "Tyler", "a b c", "", "x", "42",
         'line\\nbreak', 'tab\\there', 'quote \\"q\\"',
         'back\\\\slash', "caf\u00e9", "\u4e2d\u6587",
         "e\u0301"]

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
        return '"' + self.rng.choice(TEXTS) + '"'

# ---------- the programs family ----------
# Builders return lists of source lines, shaped on the
# barecompile fixtures (each shape oracle-confirmed
# there). A builder may be accepted in one picture and
# refused in the other; the claim is identity either
# way. The r_* builders aim at a refusal outright.

def b_scopes(g):
    r = g.rng
    a = g.fresh()
    lines = [f"let {a} = {g.num()}"]
    if r.random() < 0.5:
        b = g.fresh()
        lines.append(f"if {a} > 1 {{")
        lines.append(f"    let {b} = {a} + {g.num()}")
        lines.append(f"    while {b} > 0 {{")
        lines.append(f"        {b} = {b} - 1")
        lines.append("    }")
        lines.append("} else {")
        lines.append(f"    say {a}")
        lines.append("}")
    else:
        lines.append(f"repeat {g.num(1, 4)} {{")
        lines.append(f"    {a} = {a} + 1")
        lines.append("}")
        lines.append(f"while {a} < 100 {{")
        lines.append(f"    {a} = {a} * 2")
        lines.append("}")
    lines.append(f"say {a}")
    return lines

def b_textwork(g):
    t = g.fresh()
    u = g.fresh()
    lines = [
        f"let {t} = {g.text()}",
        f"let {u} = {t} + {g.text()}",
        f"say length({u})",
        f"say part({u}, 0, 2)",
    ]
    if len(g.rng.choice(TEXTS)) >= 0:
        lines.append(f"if {t} == {g.text()} {{")
        lines.append(f"    say {t}[0]")
        lines.append("}")
    return lines

def b_byteswork(g):
    b = g.fresh()
    return [
        f"let {b} = makebytes(4)",
        f"{b}[0] = {g.num(0, 255)}",
        f"{b}[1] = {b}[0] + 1",
        f"say {b}[1]",
        f"say length({b})",
    ]

def b_loops(g):
    t = g.fresh()
    xs = g.fresh()
    lines = [
        f"let {t} = {g.text()}",
        f"for ch in {t} {{",
        "    say ch",
        "}",
        f"let {xs} = [{g.num()}, {g.num()}, {g.num()}]",
        f"for it in {xs} {{",
        f"    say it + {g.num()}",
        "}",
    ]
    return lines

def b_defines(g):
    f = g.fresh("fn")
    p = g.fresh("p")
    q = g.fresh("q")
    return [
        f"make {f}({p}, {q}) {{",
        f"    give {p} * {q} + 1",
        "}",
        f"say {f}({g.num(1, 9)}, {g.num(1, 9)})",
    ]

def b_attempt(g):
    v = g.fresh()
    return [
        "attempt {",
        f"    let {v} = {g.num()}",
        f"    say {v}",
        "} if it fails {",
        "    say 0",
        "}",
    ]

def b_floors(g):
    r = g.rng
    a = g.fresh()
    lines = [
        f"let {a} = floor({g.num(0, 9)}) {{",
        "    mov rax, [r10]",
        "}",
        f"say {a}",
    ]
    if r.random() < 0.5:
        w = g.fresh()
        a2 = g.fresh()
        lines += [
            f"let {w} = {g.text()}",
            f"let {a2} = floor({w}, {g.num(0, 9)}) {{",
            "    mov rax, r12",
            "}",
            f"say {a2}",
        ]
    return lines

def b_desk(g):
    return [
        "let gift = guestvalue()",
        "let answer = guestgive(gift + 1)",
        "say answer",
    ]

def b_hostdoor(g):
    return [
        "define helper(x) {",
        "    give x + 1",
        "}",
        'say callguest("helper", 4)',
    ]

def r_unknown_name(g):
    return [f"say nevermade{g.n + 1}"]

def r_wrong_kind(g):
    return [f"say length({g.num()})"]

def r_unknown_tool(g):
    return [f"say nosuchtool{g.n + 1}({g.num()})"]

def r_annotation(g):
    v = g.fresh()
    return [f"let {v}: text = {g.num()}"]

ACCEPT_BUILDERS = [b_scopes, b_textwork, b_byteswork,
                   b_loops, b_defines, b_attempt,
                   b_floors, b_desk, b_hostdoor]
REFUSE_BUILDERS = [r_unknown_name, r_wrong_kind,
                   r_unknown_tool, r_annotation]

programs_dir = os.path.join(scratch, "programs")
os.makedirs(programs_dir, exist_ok=True)
rng = random.Random(59059)
for i in range(300):
    g = Gen(rng)
    lines = []
    if rng.random() < 0.3:
        lines += b_scopes(g)
        lines += rng.choice(REFUSE_BUILDERS)(g)
    else:
        for _ in range(rng.randint(1, 3)):
            lines += rng.choice(ACCEPT_BUILDERS)(g)
    with open(os.path.join(programs_dir, f"program-{i:03d}.nifla"), "wb") as fh:
        fh.write(("\n".join(lines) + "\n").encode("utf-8"))

# ---------- the numbers family ----------
# Each case is built from one kind, so the in-law
# kinds are accepted whole and the past-law kinds
# refuse at their first literal — the refusal
# speaking the value's own rendering.

def whole_digits(rng, count):
    digits = [str(rng.randint(1, 9))]
    for _ in range(count - 1):
        digits.append(str(rng.randint(0, 9)))
    return "".join(digits)

def in_law_literal(rng):
    kind = rng.randrange(4)
    if kind == 0:
        return str(rng.randint(0, 20))
    if kind == 1:
        return whole_digits(rng, rng.randint(10, 15))
    if kind == 2:
        return rng.choice(["999999999999999", "999999999999998",
                           "100000000000000", "123456789012345"])
    return whole_digits(rng, rng.randint(1, 9))

def past_law_literal(rng):
    kind = rng.randrange(6)
    if kind == 0:
        # The edge itself.
        return "1000000000000000"
    if kind == 1:
        # A fraction with a short tail.
        return whole_digits(rng, rng.randint(1, 4)) + "." + whole_digits(rng, rng.randint(1, 6))
    if kind == 2:
        # A whole too large: 16-40 digits, its refusal
        # rendering the rounded value.
        return whole_digits(rng, rng.randint(16, 40))
    if kind == 3:
        # A zero run, inside the reader's proved
        # ground: at most 21 zeros (past it, at one
        # significant digit below about 1e-22, lies
        # the number boundary — see the header).
        return "0." + "0" * rng.randint(1, 21) + str(rng.randint(1, 9))
    if kind == 4:
        # A fraction whose tail is long and mixed.
        return whole_digits(rng, rng.randint(1, 6)) + "." + whole_digits(rng, rng.randint(15, 25))
    return str(rng.randint(0, 999)) + "." + rng.choice(["5", "25", "125", "0625"])

numbers_dir = os.path.join(scratch, "numbers")
os.makedirs(numbers_dir, exist_ok=True)
rng = random.Random(59060)
for i in range(200):
    pick = in_law_literal if i % 2 == 0 else past_law_literal
    lines = []
    names = []
    for j in range(rng.randint(3, 6)):
        name = f"n{j}"
        names.append(name)
        lines.append(f"let {name} = {pick(rng)}")
    lines.append("say " + " + ".join(names))
    with open(os.path.join(numbers_dir, f"number-{i:03d}.nifla"), "wb") as fh:
        fh.write(("\n".join(lines) + "\n").encode("ascii"))

# ---------- the texts family ----------
# Literal contents are assembled as bytes: the source
# scaffolding is ASCII, the contents carry the raw
# bytes under test.

PLAIN = [b"hello", b"Tyler", b"abc", b"", b"x y z", b"42"]
ESCAPES = [b"\\n", b"\\t", b"\\\"", b"\\\\"]
UNICODE = ["caf\u00e9".encode("utf-8"),
           "\u4e2d\u6587".encode("utf-8"),
           "e\u0301".encode("utf-8"),
           "\u00e9".encode("utf-8"),
           "\U0001F468\u200d\U0001F469\u200d\U0001F467".encode("utf-8")]
CONTROLS = [c for c in range(0, 32) if c not in (10, 13)] + [127]

def text_content(rng):
    parts = []
    for _ in range(rng.randint(1, 5)):
        pick = rng.randrange(10)
        if pick <= 2:
            parts.append(rng.choice(PLAIN))
        elif pick == 3:
            parts.append(rng.choice(ESCAPES))
        elif pick == 4:
            parts.append(rng.choice(UNICODE))
        elif pick == 5:
            parts.append(b"\t")
        elif pick == 6:
            parts.append(b"\r")
        elif pick == 7:
            parts.append(b"\r\\n")
        elif pick == 8:
            parts.append(b"\r\r\\n")
        else:
            parts.append(bytes([rng.choice(CONTROLS)]))
    return b"".join(parts)

texts_dir = os.path.join(scratch, "texts")
os.makedirs(texts_dir, exist_ok=True)
rng = random.Random(59061)
for i in range(200):
    lines = []
    names = []
    for j in range(rng.randint(2, 4)):
        name = f"t{j}".encode("ascii")
        names.append(name)
        lines.append(b"let " + name + b' = "' + text_content(rng) + b'"')
    lines.append(b"say " + b" + ".join(names))
    lines.append(b"say length(" + names[0] + b")")
    with open(os.path.join(texts_dir, f"text-{i:03d}.nifla"), "wb") as fh:
        fh.write(b"\n".join(lines) + b"\n")

print("generated: programs 300, numbers 200, texts 200 (seeds 59059, 59060, 59061)")
PYEOF
[ $? -eq 0 ] || { echo "FAIL: case generation failed"; exit 1; }

fail=0
SUMMARY=""

# run_family <label> <mode> <dir> — compares the two
# sides on every generated file in <dir> under <mode>,
# and counts how many the oracle accepted (exit 0)
# against how many it refused (exit 1), both sides
# agreeing either way.
run_family() {
    label="$1"
    mode="$2"
    dir="$3"
    fpass=0
    ftotal=0
    accepted=0
    refused=0
    for f in "$dir"/*; do
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
            echo "FAIL $f (mode $mode; oracle exit $oc, front exit $fc)"
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
    echo "$label/$mode: $fpass/$ftotal ($accepted accepted, $refused refused identically)"
    SUMMARY="$SUMMARY $label/$mode $fpass/$ftotal ($accepted accepted, $refused refused),"
}

run_family programs barecompile-arm "$SCRATCH/programs"
run_family numbers barecompile-arm "$SCRATCH/numbers"
run_family texts barecompile-arm "$SCRATCH/texts"

echo "sweep:$SUMMARY"
if [ "$fail" -eq 0 ]; then
    echo "PASS barecompile-arm-sweep (Stone 60: the generated cases — bare-grammar programs, number-literal batteries and byte-built text batteries — agree byte for byte between the Nifla-written ARM refusal walk and translator and the Swift ARM bare compiler)"
else
    echo "FAIL barecompile-arm-sweep: $fail failure(s)"
    exit 1
fi
