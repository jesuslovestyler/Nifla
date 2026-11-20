#!/bin/sh
# Stone 49 proof: identity, proved whole — the generated sweep.
#
# Stones 47 and 48 proved the Nifla-written front end
# (selfhost/nifla-front.nifla) identical to the Swift front
# end (src/Lexer.swift and src/Parser.swift, through the
# proof-only oracle tools/front-oracle.swift) across the
# whole hand-written corpus and the fixture sets. This
# sweep adds generated cases no one hand-picked: a seeded
# generator (python's random.Random with fixed seeds, so
# the same cases are made on every run and any failure
# reproduces exactly) writes three families of scratch
# files, and every file is run through both front ends —
# stdout, stderr and exit code compared byte for byte,
# every run wrapped in `timeout 30`:
#
#   numbers  (300 cases, tokens mode): random digit
#     strings of length 1–40, a decimal point placed at a
#     random position or none, leading zeros allowed, some
#     with long fraction tails. Each literal stands in its
#     own small `say <lit>` file, so a disagreement names
#     its literal.
#   programs (200 cases, tree mode): complete programs
#     from a seeded grammar — make definitions (some with
#     kind annotations on parameters and '->' returns, some
#     plain), let with and without kind annotations (valid
#     kinds, maybe kinds), say lines, if/else (sometimes an
#     empty else), while, repeat, for, attempt blocks,
#     plain and target assignments, floor statements and
#     floor-with-values expressions, and expressions built
#     recursively to depth 5: number literals (some long),
#     short texts (some with escapes), true/false/nothing,
#     names, unary minus, all ten binary operators, calls
#     with 0–3 arguments, list literals, object literals
#     (field names unique within each object), field/index
#     postfix chains, parentheses. A generated program that
#     earns a refusal is compared identically — agreement
#     is agreement — but the grammar aims at mostly-valid
#     programs, so tree shapes dominate; the summary counts
#     acceptances against identical refusals.
#   soup     (200 cases, tokens mode): short files of
#     5–200 characters drawn from a Nifla-flavored
#     alphabet — ASCII letters and digits, the language's
#     symbols, backslash, space, tab, newline, carriage
#     return, and keyword fragments. No non-ASCII
#     characters (that is the boundary's territory, listed
#     in front-examples/BOUNDARY.txt) and no control
#     characters. Most of these are refusals; identical
#     refusals are exactly what this family proves.
#
# Prints per-family counts and PASS or FAIL.

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

echo "Building the oracle (untouched src/Lexer.swift + src/Parser.swift + tools/front-oracle.swift)..."
"$SWIFTC" src/Lexer.swift src/Parser.swift tools/front-oracle.swift -o "$SCRATCH/front-oracle" || { echo "FAIL: the oracle did not build"; exit 1; }

echo "Compiling the front end (selfhost/nifla-front.nifla) with niflac..."
if ! timeout 600 ./niflac selfhost/nifla-front.nifla -o "$SCRATCH/nifla-front" > "$SCRATCH/front-build.log" 2>&1; then
    echo "FAIL: niflac could not compile the front end:"
    cat "$SCRATCH/front-build.log"
    exit 1
fi

ORACLE="$SCRATCH/front-oracle"
FRONT="$SCRATCH/nifla-front"

# Generate the cases. Fixed seeds: the same files on every
# run, so a failure reproduces exactly from its family and
# index (the file names carry both).
python3 - "$SCRATCH" <<'PYEOF'
import os
import random
import sys

scratch = sys.argv[1]

NAMES = ["alpha", "beta", "gamma", "delta", "total", "count",
         "value", "result", "item", "thing", "first", "second",
         "acc", "tmp", "data", "node"]
PARAMS = ["a", "b", "c", "n", "x", "who", "each", "seed"]
FIELDS = ["name", "years", "town", "score", "left", "right",
          "head", "tail", "size", "color"]
FUNCS = ["doubleIt", "addThem", "pickOne", "compute",
         "helper", "greet", "wrapIt", "fetchIt"]
KINDS = ["number", "text", "boolean", "list", "object",
         "bytes", "nothing"]
MAYBEABLE = ["number", "text", "boolean", "list", "object",
             "bytes"]
BINOPS = ["+", "-", "*", "/", "==", "!=", "<", "<=", ">", ">="]
ASM = ["nop", "mov rax, 1", "mov rcx, 7", "add rax, rcx",
       "sub rax, 1", "xor rdx, rdx", "inc rax", "dec rcx",
       "mov r10, 3", "push rbx", "pop rbx", "mov rax, rcx"]

# ---------- numbers ----------

def digits(rng, n):
    return "".join(rng.choice("0123456789") for _ in range(n))

def number_literal(rng):
    style = rng.random()
    if style < 0.15:
        # A long fraction tail: 1-3 whole digits, 18-37 after
        # the point — never more than 40 digits in all.
        whole = digits(rng, rng.randint(1, 3))
        frac = digits(rng, rng.randint(18, 37))
        return whole + "." + frac
    if style < 0.30:
        # A long whole number: 17-40 digits.
        return digits(rng, rng.randint(17, 40))
    length = rng.randint(1, 40)
    ds = digits(rng, length)
    if length >= 2 and rng.random() < 0.55:
        pos = rng.randint(1, length - 1)
        return ds[:pos] + "." + ds[pos:]
    return ds

num_dir = os.path.join(scratch, "numbers")
os.makedirs(num_dir)
rng = random.Random(49047)
for i in range(1, 301):
    lit = number_literal(rng)
    with open(os.path.join(num_dir, f"num-{i:03d}.nifla"), "wb") as f:
        f.write(f"say {lit}\n".encode("ascii"))

# ---------- expressions & programs ----------

rng = random.Random(49048)

def kind_word(rng):
    if rng.random() < 0.30:
        return "maybe " + rng.choice(MAYBEABLE)
    return rng.choice(KINDS)

def expr_number(rng):
    r = rng.random()
    if r < 0.55:
        return str(rng.randint(0, 999))
    if r < 0.75:
        return digits(rng, rng.randint(1, 3)) + "." + digits(rng, rng.randint(1, 6))
    if r < 0.88:
        return str(rng.randint(0, 9))
    # A long literal now and then, to keep the number
    # reader honest inside trees too.
    return digits(rng, rng.randint(17, 25))

def expr_text(rng):
    # Short texts; some carry escapes. The fragments are
    # source text: \\n in this Python string is the two
    # characters backslash-n in the generated program.
    frags = ["hello", "Shalom", "a", "Tyler", "nifla", "x",
             "foo bar", "count: ", "yes", "42", "a b c",
             "don't", "dot.net", "a,b", " ", "\\n", "\\t",
             '\\"', "\\\\", "end."]
    n = rng.randint(1, 3)
    inner = "".join(rng.choice(frags) for _ in range(n))
    return '"' + inner + '"'

def leaf(rng):
    r = rng.random()
    if r < 0.34:
        return expr_number(rng)
    if r < 0.52:
        return expr_text(rng)
    if r < 0.62:
        return rng.choice(["true", "false", "nothing"])
    return rng.choice(NAMES)

def expr(rng, depth):
    if depth <= 0:
        return leaf(rng)
    r = rng.random()
    if r < 0.22:
        return leaf(rng)
    if r < 0.42:
        # A binary operation; parentheses half the time.
        left = expr(rng, depth - 1)
        right = expr(rng, depth - 1)
        body = f"{left} {rng.choice(BINOPS)} {right}"
        if rng.random() < 0.5:
            return "(" + body + ")"
        return body
    if r < 0.50:
        # Unary minus over a tighter shape.
        return "-" + expr(rng, depth - 1)
    if r < 0.60:
        # A call with 0-3 arguments.
        nargs = rng.randint(0, 3)
        args = ", ".join(expr(rng, depth - 1) for _ in range(nargs))
        return f"{rng.choice(FUNCS)}({args})"
    if r < 0.70:
        # A list literal with 0-3 items.
        n = rng.randint(0, 3)
        items = ", ".join(expr(rng, depth - 1) for _ in range(n))
        return "[" + items + "]"
    if r < 0.80:
        # An object literal; field names unique within it.
        n = rng.randint(0, 3)
        fields = rng.sample(FIELDS, n)
        pairs = ", ".join(f"{name}: {expr(rng, depth - 1)}" for name in fields)
        return "{" + pairs + "}"
    if r < 0.90:
        # A postfix chain over a name, a call, a literal, or
        # a parenthesized expression.
        base_kind = rng.random()
        if base_kind < 0.45:
            base = rng.choice(NAMES)
        elif base_kind < 0.65:
            base = f"{rng.choice(FUNCS)}({expr(rng, depth - 1)})"
        elif base_kind < 0.80:
            base = "{" + ", ".join(
                f"{name}: {expr(rng, depth - 1)}"
                for name in rng.sample(FIELDS, rng.randint(1, 2))) + "}"
        elif base_kind < 0.90:
            base = "[" + ", ".join(expr(rng, depth - 1)
                                    for _ in range(rng.randint(1, 2))) + "]"
        else:
            base = "(" + expr(rng, depth - 1) + ")"
        steps = ""
        for _ in range(rng.randint(1, 3)):
            if rng.random() < 0.5:
                steps += "." + rng.choice(FIELDS)
            else:
                steps += "[" + expr(rng, depth - 1) + "]"
        return base + steps
    return "(" + expr(rng, depth - 1) + ")"

def floor_block(rng, with_values):
    lines = []
    if with_values:
        nargs = rng.randint(0, 2)
        args = ", ".join(expr(rng, 1) for _ in range(nargs))
        lines.append(f"floor({args}) {{")
    else:
        lines.append("floor {")
    for _ in range(rng.randint(1, 3)):
        lines.append("    " + rng.choice(ASM))
    lines.append("}")
    return "\n".join(lines)

def block(rng, depth, in_function, allow_floor):
    n = rng.randint(0, 3)
    stmts = [stmt(rng, depth, in_function, allow_floor)
             for _ in range(n)]
    if not stmts:
        return "{\n}"
    return "{\n" + "\n".join(stmts) + "\n}"

def stmt(rng, depth, in_function, allow_floor):
    choices = ["let", "say", "assign", "target", "docall"]
    if depth < 3:
        choices += ["if", "while", "repeat", "for",
                    "attempt", "make"]
    if in_function:
        choices += ["give", "give"]
    if allow_floor:
        choices += ["floor"]
    what = rng.choice(choices)
    if what == "let":
        name = rng.choice(NAMES)
        if rng.random() < 0.35:
            ann = ": " + kind_word(rng) + " "
        else:
            ann = " "
        if allow_floor and rng.random() < 0.10:
            return f"let {name} = " + floor_block(rng, rng.random() < 0.5)
        return f"let {name}{ann}= {expr(rng, 3)}"
    if what == "say":
        if allow_floor and rng.random() < 0.10:
            return "say " + floor_block(rng, rng.random() < 0.5)
        return "say " + expr(rng, 3)
    if what == "assign":
        return f"{rng.choice(NAMES)} = {expr(rng, 3)}"
    if what == "target":
        target = rng.choice(NAMES)
        for _ in range(rng.randint(1, 3)):
            if rng.random() < 0.5:
                target += "." + rng.choice(FIELDS)
            else:
                target += "[" + expr(rng, 2) + "]"
        return f"{target} = {expr(rng, 3)}"
    if what == "docall":
        nargs = rng.randint(0, 3)
        args = ", ".join(expr(rng, 2) for _ in range(nargs))
        return f"{rng.choice(FUNCS)}({args})"
    if what == "give":
        return "give " + expr(rng, 3)
    if what == "if":
        head = "if " + expr(rng, 2) + " " + \
            block(rng, depth + 1, in_function, allow_floor)
        r = rng.random()
        if r < 0.40:
            return head
        if r < 0.55:
            # A present-but-empty else.
            return head + " else {\n}"
        return head + " else " + \
            block(rng, depth + 1, in_function, allow_floor)
    if what == "while":
        return "while " + expr(rng, 2) + " " + \
            block(rng, depth + 1, in_function, allow_floor)
    if what == "repeat":
        return "repeat " + expr(rng, 2) + " " + \
            block(rng, depth + 1, in_function, allow_floor)
    if what == "for":
        return (f"for {rng.choice(PARAMS)} in {expr(rng, 2)} "
                + block(rng, depth + 1, in_function, allow_floor))
    if what == "attempt":
        return ("attempt " + block(rng, depth + 1, in_function, allow_floor)
                + " if it fails "
                + block(rng, depth + 1, in_function, allow_floor))
    if what == "make":
        name = rng.choice(FUNCS)
        params = rng.sample(PARAMS, rng.randint(0, 3))
        parts = []
        for p in params:
            if rng.random() < 0.40:
                parts.append(f"{p}: {kind_word(rng)}")
            else:
                parts.append(p)
        sig = f"make {name}(" + ", ".join(parts) + ")"
        if rng.random() < 0.40:
            sig += " -> " + kind_word(rng)
        return sig + " " + block(rng, depth + 1, True, allow_floor)
    # A floor block standing on its own line.
    return floor_block(rng, rng.random() < 0.5)

prog_dir = os.path.join(scratch, "programs")
os.makedirs(prog_dir)
for i in range(1, 201):
    n = rng.randint(3, 9)
    lines = [f"// generated program {i} (seed 49048)"]
    for _ in range(n):
        lines.append(stmt(rng, 0, False, True))
    text = "\n".join(lines) + "\n"
    with open(os.path.join(prog_dir, f"prog-{i:03d}.nifla"), "wb") as f:
        f.write(text.encode("ascii"))

# ---------- token soup ----------

rng = random.Random(49049)
charset = ("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
           "0123456789"
           "+-*/(){}[]=<>.,:\"!\\ \t\n\r")
fragments = ["let", "flo", "say", "//", "/*"]
soup_dir = os.path.join(scratch, "soup")
os.makedirs(soup_dir)
for i in range(1, 201):
    target = rng.randint(5, 200)
    pieces = []
    length = 0
    while length < target:
        if rng.random() < 0.18:
            piece = rng.choice(fragments)
        else:
            piece = rng.choice(charset)
        pieces.append(piece)
        length += len(piece)
    text = "".join(pieces)[:200]
    if len(text) < 5:
        text = text + "a" * (5 - len(text))
    with open(os.path.join(soup_dir, f"soup-{i:03d}.nifla"), "wb") as f:
        f.write(text.encode("ascii"))

print("generated: numbers 300, programs 200, soup 200 (seeds 49047, 49048, 49049)")
PYEOF
[ $? -eq 0 ] || { echo "FAIL: case generation failed"; exit 1; }

fail=0
SUMMARY=""

# run_family <label> <mode> <dir> — compares the two front
# ends on every generated file in <dir>, and counts how
# many the oracle accepted (exit 0) against how many it
# refused (exit 1), both sides agreeing either way.
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
    SUMMARY="$SUMMARY $label $fpass/$ftotal,"
}

run_family numbers tokens "$SCRATCH/numbers"
run_family programs tree "$SCRATCH/programs"
run_family soup tokens "$SCRATCH/soup"

echo "sweep:$SUMMARY"
if [ "$fail" -eq 0 ]; then
    echo "PASS front-sweep (Stone 49: the generated cases — numbers, programs and token soup — agree byte for byte between the Nifla-written front end and the Swift front end)"
else
    echo "FAIL front-sweep: $fail failure(s)"
    exit 1
fi
