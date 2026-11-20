#!/bin/sh
# Stone 54 proof: identity, proved whole — the generated
# sweep for the compiler.
#
# Stone 53 proved the Nifla-written translator
# (selfhost/nifla-front.nifla's compile mode) identical
# to the Swift translator (SwiftTranslator in
# src/Compiler.swift, through the proof-only oracle
# tools/compile-oracle.swift) across the whole
# hand-written corpus and the 10 fixtures in
# compile-examples/. This sweep adds generated cases no
# one hand-picked: a seeded generator (python's
# random.Random with fixed seeds, so the same cases are
# made on every run and any failure reproduces exactly)
# writes three families of scratch files, and every
# file is run through both translators — stdout, stderr
# and exit code compared byte for byte, every run
# wrapped in `timeout 30`:
#
#   programs (300 cases, compile mode): complete
#     programs from a seeded grammar aimed at
#     translation shapes — nested scopes of every
#     statement kind (so the fresh-name counter's
#     order is exercised hard), defines with mixed
#     kind marks, attempts with gives, field and
#     index targets, deep expressions, floor blocks
#     in the positions the language allows — mixed
#     with checker-refused programs, whose refusal
#     identity is compared the same way. Each case is
#     built aiming at acceptance or at refusal; the
#     summary counts the split the oracle actually
#     gave.
#   numbers  (250 cases, compile mode): lets and
#     says whose literals are generated digit
#     strings — whole parts of 1–20 digits straddling
#     the 1e15 / 9e15 / 2^53 boundaries, fractions
#     with long tails and zero runs, whole strings of
#     21–40 digits (past the reader's exact keeping,
#     so the second-mantissa path is exercised) — so
#     cmpSwiftNumber's one patch and Swift's Double
#     text are compared where they can drift. The
#     generated literals stay inside the number
#     reader's proved ground by design: fractions no
#     deeper than 22 digits of scale, wholes no
#     longer than 40 digits. Past that ground lies
#     the number boundary — short digit strings at
#     extreme scales, and digit strings hundreds
#     long, may be read one ulp away from Swift —
#     recorded with its pattern named and its
#     fixtures pinned in front-examples/BOUNDARY.txt,
#     where the corpus proofs verify the divergence
#     on every run; that is the boundary's territory,
#     already recorded, exactly as the check sweep
#     stays inside ASCII by design.
#   texts    (200 cases, compile mode): lets and
#     says whose text literals are assembled byte by
#     byte from fragments — plain words, the four
#     escapes, text past the ASCII edge (accented
#     letters, a combining sequence, CJK, an emoji
#     with a joiner), raw tab bytes, raw carriage
#     returns (alone, doubled, and standing before
#     the \n escape, where the value's CR and LF
#     meet as one cluster on the port's walk and two
#     scalars on Swift's), and raw control bytes
#     sampled from the codes 0–31 and 127 — so
#     cmpSwiftText's pair rule and its byte-built
#     control lookup are compared where they can
#     drift. (A raw line feed never stands in a
#     literal: the lexer refuses it, on both sides,
#     already proved by the corpus.)
#
# Names stay ASCII in every family by design — word
# characters past Latin-1 are the front end's
# standing boundary, already recorded; values go
# past ASCII deliberately, because values are not
# the boundary.
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

echo "Building the oracle (untouched src/Lexer.swift + src/Parser.swift + src/Interpreter.swift + src/BareCompiler.swift + src/Checker.swift + src/Compiler.swift + src/BareCompilerARM.swift + tools/compile-oracle.swift)..."
"$SWIFTC" src/Lexer.swift src/Parser.swift src/Interpreter.swift src/BareCompiler.swift src/Checker.swift src/Compiler.swift src/BareCompilerARM.swift tools/compile-oracle.swift -o "$SCRATCH/compile-oracle" || { echo "FAIL: the oracle did not build"; exit 1; }

echo "Compiling the front end (selfhost/nifla-front.nifla) with niflac..."
if ! timeout 600 ./niflac selfhost/nifla-front.nifla -o "$SCRATCH/nifla-front" > "$SCRATCH/front-build.log" 2>&1; then
    echo "FAIL: niflac could not compile the front end:"
    cat "$SCRATCH/front-build.log"
    exit 1
fi

ORACLE="$SCRATCH/compile-oracle"
FRONT="$SCRATCH/nifla-front"

# Generate the cases. Fixed seeds: the same files on
# every run, so a failure reproduces exactly from its
# family and index (the file names carry both).
python3 - "$SCRATCH" <<'PYEOF'
import os
import random
import sys

scratch = sys.argv[1]

# ---------- shared helpers ----------

TEXTS = ["hello", "Tyler", "a b c", "", "x", "42",
         'line\\nbreak', 'tab\\there', 'quote \\"q\\"',
         'back\\\\slash', "caf\u00e9", "\u4e2d\u6587",
         "\u0391\u03bb\u03c6\u03b1", "e\u0301",
         "\U0001F468\u200d\U0001F469\u200d\U0001F467"]

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
# Builders return lists of source lines. Each aims at
# acceptance (the translation is the claim) except the
# r_* builders, which aim at a checker refusal whose
# words must agree.

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

def b_define_mixed(g):
    r = g.rng
    f = g.fresh("fn")
    p1, p2, p3 = g.fresh("p"), g.fresh("p"), g.fresh("p")
    marks = r.choice([
        f"make {f}({p1}: number, {p2}, {p3}: text) -> number {{",
        f"make {f}({p1}, {p2}) {{",
        f"make {f}({p1}: text) -> text {{",
    ])
    if "-> text" in marks:
        body = [f"    give {p1} + {g.text()}"]
        call = f"{f}({g.text()})"
    elif "-> number" in marks:
        body = [f"    give {p1} + length({p3})"]
        call = f"{f}({g.num()}, {g.num()}, {g.text()})"
    else:
        body = [f"    give {p1} + {p2}"]
        call = f"{f}({g.num()}, {g.num()})"
    out = g.fresh()
    return [marks] + body + ["}", f"let {out} = {call}", f"say {out}"]

def b_attempt(g):
    r = g.rng
    if r.random() < 0.5:
        f = g.fresh("fn")
        p = g.fresh("p")
        return [
            f"make {f}({p}) {{",
            "    attempt {",
            f"        if {p} > 1 {{",
            f"            give {p}",
            "        }",
            "    } if it fails {",
            "        give 0 - 1",
            "    }",
            "    give 0",
            "}",
            f"say {f}({g.num()})",
        ]
    v = g.fresh()
    return [
        "attempt {",
        f"    let {v} = {g.num()}",
        f"    say {v}",
        "} if it fails {",
        "    say problem",
        "}",
    ]

def b_targets(g):
    o = g.fresh()
    lines = [
        f"let {o} = {{ name: {g.text()}, scores: [{g.num()}, {g.num()}, {g.num()}] }}",
        f"{o}.name = {g.text()}",
        f"{o}.scores[1] = {o}.scores[0] + {o}.scores[2]",
    ]
    gr = g.fresh()
    lines.append(f"let {gr} = [[{g.num()}, {g.num()}], [{g.num()}, {g.num()}]]")
    lines.append(f"{gr}[1][0] = {gr}[0][1]")
    lines.append(f"say {o}.name")
    return lines

def b_floors(g):
    r = g.rng
    a = g.fresh()
    lines = [
        f"let {a} = floor({g.num(0, 9)}) {{",
        "    mov rax, [r10]",
        "}",
    ]
    if r.random() < 0.5:
        b = g.fresh()
        lines += [
            f"let {b} = floor({g.num(0, 9)}, {g.num(0, 9)}) {{",
            "    mov rax, [r10]",
            "    add rax, [r10 + 8]",
            "}",
            f"say {a} + {b}",
        ]
    else:
        lines.append(f"say {a}")
    return lines

def b_expr_soup(g):
    v = g.fresh()
    w = g.fresh()
    return [
        f"let {v} = {g.num(1, 9)}",
        f"let {w} = [{v}, {v} + 1, -{v}]",
        f"say ({v} + {w}[1]) * 2 - {w}[2]",
        f"say length({g.text()} + {g.text()})",
        f"say part({g.text()}, 0, 2) + join([{g.text()}, {g.text()}], \"-\")",
    ]

def b_loops_for(g):
    r = g.rng
    t = g.fresh()
    lines = [f"let {t} = {g.text()}"]
    lines.append(f"for ch in {t} {{")
    lines.append("    say ch")
    lines.append("}")
    xs = g.fresh()
    lines.append(f"let {xs} = [{g.num()}, {g.num()}]")
    lines.append(f"for it in {xs} {{")
    lines.append(f"    say it + {g.num()}")
    lines.append("}")
    return lines

def b_annotated(g):
    v = g.fresh()
    w = g.fresh()
    return [
        f"let {v}: number = {g.num()}",
        f"let {w}: text = {g.text()}",
        f"{v} = {v} + {g.num()}",
        f"say {w} + {v}",
    ]

def r_unknown_name(g):
    return [f"say nevermade{g.n + 1}"]

def r_wrong_kind(g):
    return [f"say length({g.num()})"]

def r_annotation(g):
    v = g.fresh()
    return [f"let {v}: text = {g.num()}"]

def r_div_zero(g):
    v = g.fresh()
    return [f"let {v} = 10 / 0"]

def r_unknown_function(g):
    return [f"say nosuchtool{g.n + 1}({g.num()})"]

ACCEPT_BUILDERS = [b_scopes, b_define_mixed, b_attempt,
                   b_targets, b_floors, b_expr_soup,
                   b_loops_for, b_annotated]
REFUSE_BUILDERS = [r_unknown_name, r_wrong_kind,
                   r_annotation, r_div_zero,
                   r_unknown_function]

programs_dir = os.path.join(scratch, "programs")
os.makedirs(programs_dir, exist_ok=True)
rng = random.Random(53053)
for i in range(300):
    g = Gen(rng)
    lines = []
    if rng.random() < 0.3:
        # A refusal case: one clean part, then the refusal.
        lines += b_scopes(g)
        lines += rng.choice(REFUSE_BUILDERS)(g)
    else:
        for _ in range(rng.randint(1, 3)):
            lines += rng.choice(ACCEPT_BUILDERS)(g)
    with open(os.path.join(programs_dir, f"program-{i:03d}.nifla"), "wb") as fh:
        fh.write(("\n".join(lines) + "\n").encode("utf-8"))

# ---------- the numbers family ----------

def whole_digits(rng, count):
    digits = [str(rng.randint(1, 9))]
    for _ in range(count - 1):
        digits.append(str(rng.randint(0, 9)))
    return "".join(digits)

def num_literal(rng):
    kind = rng.randrange(9)
    if kind == 0:
        return str(rng.randint(0, 20))
    if kind == 1:
        return whole_digits(rng, rng.randint(1, 20))
    if kind == 2:
        # Straddle a boundary: a boundary's digits with
        # the last few perturbed.
        base = rng.choice(["999999999999999", "1000000000000000",
                           "8999999999999999", "9000000000000000",
                           "9007199254740991", "9007199254740993",
                           "9999999999999999", "10000000000000000"])
        chars = list(base)
        for _ in range(rng.randint(0, 2)):
            pos = rng.randrange(len(chars))
            chars[pos] = str(rng.randint(0, 9))
        return "".join(chars)
    if kind == 3:
        return whole_digits(rng, rng.randint(1, 6)) + "." + whole_digits(rng, rng.randint(1, 17))
    if kind == 4:
        # A zero run, inside the reader's proved
        # ground: at most 21 zeros, so the scale stays
        # at 1e-22 or larger (past it lies the number
        # boundary — see the header).
        return "0." + "0" * rng.randint(1, 21) + str(rng.randint(1, 9))
    if kind == 5:
        # A whole string past the exact keeping (17
        # digits), inside the proved ground: 21–40
        # digits (hundreds long lies past the number
        # boundary — see the header).
        return whole_digits(rng, rng.randint(21, 40))
    if kind == 6:
        # The deep end of the proved ground: a zero
        # run of 15–21 and one significant digit.
        return "0." + "0" * rng.randint(15, 21) + str(rng.randint(1, 9))
    if kind == 7:
        return str(rng.randint(0, 999)) + "." + rng.choice(["0", "00", "50", "2500", "125000"])
    # kind == 8: a fraction whose tail is long and mixed.
    return whole_digits(rng, rng.randint(1, 12)) + "." + whole_digits(rng, rng.randint(15, 25))

numbers_dir = os.path.join(scratch, "numbers")
os.makedirs(numbers_dir, exist_ok=True)
rng = random.Random(53054)
for i in range(250):
    lines = []
    names = []
    for j in range(rng.randint(3, 6)):
        name = f"n{j}"
        names.append(name)
        lines.append(f"let {name} = {num_literal(rng)}")
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
           "\u0391\u03bb\u03c6\u03b1".encode("utf-8"),
           "e\u0301".encode("utf-8"),
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
            parts.append(b"\t")            # a raw tab
        elif pick == 6:
            parts.append(b"\r")            # a raw CR, standing alone
        elif pick == 7:
            parts.append(b"\r\\n")         # a raw CR, then the \n escape
        elif pick == 8:
            parts.append(b"\r\r\\n")       # two raw CRs, then the escape
        else:
            parts.append(bytes([rng.choice(CONTROLS)]))
    return b"".join(parts)

texts_dir = os.path.join(scratch, "texts")
os.makedirs(texts_dir, exist_ok=True)
rng = random.Random(53055)
for i in range(200):
    lines = []
    names = []
    for j in range(rng.randint(2, 4)):
        name = f"t{j}".encode("ascii")
        names.append(name)
        lines.append(b"let " + name + b' = "' + text_content(rng) + b'"')
    lines.append(b"say " + b" + ".join(names))
    with open(os.path.join(texts_dir, f"text-{i:03d}.nifla"), "wb") as fh:
        fh.write(b"\n".join(lines) + b"\n")

print("generated: programs 300, numbers 250, texts 200 (seeds 53053, 53054, 53055)")
PYEOF
[ $? -eq 0 ] || { echo "FAIL: case generation failed"; exit 1; }

fail=0
SUMMARY=""

# run_family <label> <dir> — compares the two
# translators on every generated file in <dir>, and
# counts how many the oracle accepted (exit 0)
# against how many it refused (exit 1), both sides
# agreeing either way.
run_family() {
    label="$1"
    dir="$2"
    fpass=0
    ftotal=0
    accepted=0
    refused=0
    for f in "$dir"/*.nifla; do
        [ -f "$f" ] || continue
        ftotal=$((ftotal + 1))
        timeout 30 "$ORACLE" compile "$f" > "$SCRATCH/o.out" 2> "$SCRATCH/o.err"
        oc=$?
        timeout 30 "$FRONT" compile "$f" > "$SCRATCH/f.out" 2> "$SCRATCH/f.err"
        fc=$?
        if [ "$oc" -eq 0 ]; then
            accepted=$((accepted + 1))
        elif [ "$oc" -eq 1 ]; then
            refused=$((refused + 1))
        fi
        if [ "$oc" -eq "$fc" ] && cmp -s "$SCRATCH/o.out" "$SCRATCH/f.out" && cmp -s "$SCRATCH/o.err" "$SCRATCH/f.err"; then
            fpass=$((fpass + 1))
        else
            echo "FAIL $f (oracle exit $oc, front exit $fc)"
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

run_family programs "$SCRATCH/programs"
run_family numbers "$SCRATCH/numbers"
run_family texts "$SCRATCH/texts"

echo "sweep:$SUMMARY"
if [ "$fail" -eq 0 ]; then
    echo "PASS compile-sweep (Stone 54: the generated cases — translation-shape programs, number-literal batteries and byte-built text batteries — agree byte for byte between the Nifla-written translator and the Swift translator)"
else
    echo "FAIL compile-sweep: $fail failure(s)"
    exit 1
fi
