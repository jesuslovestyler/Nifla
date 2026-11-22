#!/bin/sh
# Stone 56 proof: the bare translator stands in Nifla.
#
# selfhost/nifla-front.nifla — the toolchain front end
# written in Nifla, this leg carrying the bare
# translator beside the lexer, the parser, the checker,
# the compiler's translator and the bare validator —
# must agree with the Swift bare translator
# (BareTranslator in src/BareCompiler.swift) in its
# barecompile mode: the same emitted assembly on
# standard output for a program the whole road
# accepts, the same refusal on standard error, the
# same exit code, on every file of the corpus:
#
#   barecompile-examples/*.nifla (the Stone 56
#     translator fixtures) and bare-examples/*.nifla
#     and barevalid-examples/*.nifla — each walked the
#     whole bare road in the host picture: lex, parse,
#     check in the bare picture, validate, translate;
#   examples/, checker-examples/, floor-examples/,
#     voice-examples/, selfhost (2), tools (1), every
#     fenced nifla block in PRIMER.md and TUTORIAL.md,
#     front-examples/*.nifla (the fixtures — lex/parse/
#     check refusals agree through the front end, and
#     the bare road's verdict then agrees or refuses
#     identically), check-examples/*.nifla,
#     compile-examples/*.nifla, and the Cardnull OS 2
#     sources (read-only) — for most of these the bare
#     road refuses at the check or the validator, and
#     the claim there is refusal identity; where it
#     accepts, the claim is the assembly itself, byte
#     for byte.
#
# The Swift side is spoken for by a proof-only oracle
# (tools/bare-oracle.swift) that links the untouched
# src/Lexer.swift, src/Parser.swift,
# src/Interpreter.swift, src/BareCompiler.swift,
# src/Checker.swift and src/Compiler.swift — plus
# src/BareCompilerARM.swift, which the link pulls in
# (Compiler.swift reaches the ARM bare compiler). The
# oracle's translator is made with no video request,
# as a build without the flag is; the video request
# is driver input, as Stone 56's ledger records.
#
# The fixtures named in front-examples/BOUNDARY.txt
# diverge in the barecompile mode, as in the bare
# proofs, and must DISAGREE here too — the word
# fixtures at the lex stage, and the number fixtures
# in the value the validator's refusal carries, the
# refusal speaking before any translation.
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

echo "Building the oracle (untouched src/Lexer.swift + src/Parser.swift + src/Interpreter.swift + src/BareCompiler.swift + src/Checker.swift + src/Compiler.swift + src/BareCompilerARM.swift + tools/bare-oracle.swift)..."
"$SWIFTC" src/Lexer.swift src/Parser.swift src/Interpreter.swift src/BareCompiler.swift src/Checker.swift src/Compiler.swift src/BareCompilerARM.swift tools/bare-oracle.swift -o "$SCRATCH/bare-oracle" || { echo "FAIL: the oracle did not build"; exit 1; }

echo "Compiling the front end (selfhost/nifla-front.nifla) with niflac..."
if ! timeout 600 ./niflac selfhost/nifla-front.nifla -o "$SCRATCH/nifla-front" > "$SCRATCH/front-build.log" 2>&1; then
    echo "FAIL: niflac could not compile the front end:"
    cat "$SCRATCH/front-build.log"
    exit 1
fi

ORACLE="$SCRATCH/bare-oracle"
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
# barecompile results on every file; boundary fixtures
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
        timeout 300 "$ORACLE" barecompile "$f" > "$SCRATCH/o.out" 2> "$SCRATCH/o.err"
        oc=$?
        timeout 300 "$FRONT" barecompile "$f" > "$SCRATCH/f.out" 2> "$SCRATCH/f.err"
        fc=$?
        agree=0
        if [ "$oc" -eq "$fc" ] && cmp -s "$SCRATCH/o.out" "$SCRATCH/f.out" && cmp -s "$SCRATCH/o.err" "$SCRATCH/f.err"; then
            agree=1
        fi
        if [ "$label" = "fixtures" ] && is_boundary "$f"; then
            if [ "$agree" -eq 1 ]; then
                echo "FAIL $f (named in BOUNDARY.txt but the two sides AGREE in barecompile mode — the boundary list is stale and must be revisited)"
                fail=$((fail + 1))
            else
                echo "BOUNDARY $f (verified divergent: oracle exit $oc, front exit $fc)"
                gpass=$((gpass + 1))
            fi
            continue
        fi
        if [ "$agree" -eq 1 ]; then
            echo "PASS $f"
            pass=$((pass + 1))
            gpass=$((gpass + 1))
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

run_group bcfix barecompile-examples/*.nifla
run_group bare bare-examples/*.nifla
run_group bvfix barevalid-examples/*.nifla
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

CARDNULL_DIR="$HOME/workspace/cardnull-os-2/src"
if [ -d "$CARDNULL_DIR" ]; then
    run_group cardnull "$CARDNULL_DIR"/*.nifla
else
    echo "SKIP cardnull (directory $CARDNULL_DIR is absent)"
    GROUP_RESULTS="$GROUP_RESULTS cardnull SKIPPED,"
fi

boundary_count=$(wc -l < "$BOUNDARY_LIST" | tr -d ' ')
echo "barecompile:$GROUP_RESULTS boundary $boundary_count noted"
if [ "$fail" -ne 0 ]; then
    echo "FAIL barecompile: $fail failure(s)"
    exit 1
fi
echo "PASS barecompile (Stone 56: the Nifla-written bare translator's emitted assembly is byte-identical to the Swift bare translator's across the whole corpus:$GROUP_RESULTS boundary $boundary_count noted)"
