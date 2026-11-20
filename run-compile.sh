#!/bin/sh
# Stone 54 gate: the compiler leg's single command.
#
# This script is the gate for the whole compiler leg:
# it runs the corpus proof (Stone 53, as it stands —
# the translator stands in the front end's compile
# mode) and then the generated sweep
# (run-compile-sweep.sh, Stone 54), stopping at the
# first failure, and on success prints one closing
# summary naming the whole claim.
#
# The corpus proof:
#
# selfhost/nifla-front.nifla — the toolchain front end
# written in Nifla, this leg carrying the compiler's
# translator beside the lexer, the parser and the
# checker — must agree with the Swift translator
# (SwiftTranslator in src/Compiler.swift) in its
# compile mode: the same generated Swift on standard
# output for an accepted program, the same refusal on
# standard error, the same exit code, on every file of
# the corpus:
#
#   examples/, checker-examples/ (45 — each must
#     REFUSE at the check stage, and the refusal must
#     also equal its .error file byte for byte),
#     floor-examples/, voice-examples/, selfhost (2),
#     tools (1), every fenced nifla block in PRIMER.md
#     and TUTORIAL.md, front-examples/*.nifla (104
#     fixtures — lex/parse/check refusals agree through
#     the front end, acceptances then translate),
#     check-examples/*.nifla (the checker fixtures),
#     compile-examples/*.nifla (the Stone 53 translator
#     fixtures), bare-examples/ and the Cardnull OS 2
#     sources (read-only) — the last two in the hosted
#     picture, where the compiled door refuses most of
#     them at the check stage; the refusal identity is
#     the claim there.
#
# The Swift side is spoken for by a proof-only oracle
# (tools/compile-oracle.swift) that links the
# untouched src/Lexer.swift, src/Parser.swift,
# src/Interpreter.swift, src/BareCompiler.swift,
# src/Checker.swift and src/Compiler.swift — plus
# src/BareCompilerARM.swift, which the link pulls in
# (Compiler.swift reaches the ARM bare compiler).
#
# The fixtures named in front-examples/BOUNDARY.txt
# diverge in compile mode, as in the front proofs,
# and must DISAGREE here too — the word fixtures at
# the lex stage, and the number fixtures (Stone 54)
# in the value the generated Swift carries.
#
# Prints PASS or FAIL per file and a summary with
# per-group counts and the claim.

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

# Extract the books' nifla blocks into scratch .nifla files.
python3 - "$SCRATCH" <<'PYEOF'
import os
import sys

scratch = sys.argv[1]
for book, tag in (("PRIMER.md", "primer"), ("TUTORIAL.md", "tutorial")):
    text = open(book, encoding="utf-8").read()
    blocks = []
    pos = 0
    while True:
        start = text.find("```", pos)
        if start < 0:
            break
        end_of_line = text.find("\n", start)
        info = text[start + 3:end_of_line].strip()
        close = text.find("```", end_of_line)
        if close < 0:
            print(f"FAIL: an unclosed fenced block in {book}")
            sys.exit(1)
        body = text[end_of_line + 1:close]
        blocks.append((info, body))
        pos = close + 3
    outdir = os.path.join(scratch, tag)
    os.makedirs(outdir, exist_ok=True)
    n = 0
    for info, body in blocks:
        if info.startswith("nifla"):
            n += 1
            with open(os.path.join(outdir, f"{tag}-{n:03d}.nifla"), "w", encoding="utf-8") as f:
                f.write(body)
    print(f"{book}: {n} nifla blocks extracted")
PYEOF
[ $? -eq 0 ] || { echo "FAIL: book extraction failed"; exit 1; }

# The boundary list: fixture basenames, one per non-comment line.
BOUNDARY_LIST="$SCRATCH/boundary.txt"
grep -v '^[[:space:]]*#' front-examples/BOUNDARY.txt | grep -v '^[[:space:]]*$' | awk '{print $1}' > "$BOUNDARY_LIST"

is_boundary() {
    grep -qx "$(basename "$1")" "$BOUNDARY_LIST"
}

pass=0
fail=0

# run_group <label> <files...> — compares the two
# compile results on every file; boundary fixtures
# (the fixtures group only) must diverge instead.
GROUP_RESULTS=""
run_group() {
    label="$1"
    shift
    gpass=0
    gtotal=0
    for f in "$@"; do
        [ -f "$f" ] || continue
        gtotal=$((gtotal + 1))
        timeout 120 "$ORACLE" compile "$f" > "$SCRATCH/o.out" 2> "$SCRATCH/o.err"
        oc=$?
        timeout 120 "$FRONT" compile "$f" > "$SCRATCH/f.out" 2> "$SCRATCH/f.err"
        fc=$?
        agree=0
        if [ "$oc" -eq "$fc" ] && cmp -s "$SCRATCH/o.out" "$SCRATCH/f.out" && cmp -s "$SCRATCH/o.err" "$SCRATCH/f.err"; then
            agree=1
        fi
        if [ "$label" = "fixtures" ] && is_boundary "$f"; then
            if [ "$agree" -eq 1 ]; then
                echo "FAIL $f (named in BOUNDARY.txt but the two sides AGREE in compile mode — the boundary list is stale and must be revisited)"
                fail=$((fail + 1))
            else
                echo "BOUNDARY $f (verified divergent: oracle exit $oc, front exit $fc)"
                gpass=$((gpass + 1))
            fi
            continue
        fi
        if [ "$agree" -eq 1 ]; then
            ok=1
            if [ "$label" = "checker" ]; then
                # Each checker example must REFUSE, and the
                # refusal must equal its .error file.
                if [ "$oc" -eq 0 ]; then
                    echo "FAIL $f (checker example was ACCEPTED by both sides; it must refuse)"
                    ok=0
                elif ! cmp -s "$SCRATCH/o.err" "${f%.nifla}.error"; then
                    echo "FAIL $f (the agreed refusal does not equal its .error file)"
                    echo "--- .error vs oracle stderr:"
                    diff "${f%.nifla}.error" "$SCRATCH/o.err" | head -n 20
                    ok=0
                fi
            fi
            if [ "$ok" -eq 1 ]; then
                echo "PASS $f"
                pass=$((pass + 1))
                gpass=$((gpass + 1))
            else
                fail=$((fail + 1))
            fi
        else
            echo "FAIL $f (oracle exit $oc, front exit $fc)"
            echo "--- stdout diff (oracle vs front):"
            diff "$SCRATCH/o.out" "$SCRATCH/f.out" | head -n 20
            echo "--- stderr diff (oracle vs front):"
            diff "$SCRATCH/o.err" "$SCRATCH/f.err" | head -n 20
            fail=$((fail + 1))
        fi
    done
    GROUP_RESULTS="$GROUP_RESULTS $label $gpass/$gtotal,"
}

run_group examples examples/*.nifla
run_group checker checker-examples/*.nifla
run_group floor floor-examples/*.nifla
run_group voice voice-examples/*.nifla
run_group selfhost selfhost/nifla-in-nifla.nifla selfhost/nifla-front.nifla
run_group tools tools/feathercheck.nifla
run_group primer "$SCRATCH"/primer/*.nifla
run_group tutorial "$SCRATCH"/tutorial/*.nifla
run_group fixtures front-examples/*.nifla
run_group checkfix check-examples/*.nifla
run_group cmpfix compile-examples/*.nifla
run_group bare bare-examples/*.nifla

CARDNULL_DIR="$HOME/workspace/cardnull-os-2/src"
if [ -d "$CARDNULL_DIR" ]; then
    run_group cardnull "$CARDNULL_DIR"/*.nifla
else
    echo "SKIP cardnull (directory $CARDNULL_DIR is absent)"
    GROUP_RESULTS="$GROUP_RESULTS cardnull SKIPPED,"
fi

boundary_count=$(wc -l < "$BOUNDARY_LIST" | tr -d ' ')
echo "compile:$GROUP_RESULTS boundary $boundary_count noted"
if [ "$fail" -ne 0 ]; then
    echo "FAIL compile: $fail failure(s)"
    exit 1
fi

# Stone 54: the generated sweep, after the corpus proof.
# The gate stops at the first failure.
./run-compile-sweep.sh || { echo "FAIL compile-gate: the generated sweep failed — the gate stops here"; exit 1; }

echo "PASS compile-gate (Stone 54: the Nifla-written translator's generated Swift is byte-identical to the Swift translator's across the whole corpus:$GROUP_RESULTS and the 10 fixtures in compile-examples/, and across the generated sweep of 300 translation-shape programs (205 accepted, 95 refused identically), 250 number-literal programs and 200 byte-built text programs, boundary $boundary_count noted)"
