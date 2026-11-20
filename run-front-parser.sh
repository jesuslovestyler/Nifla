#!/bin/sh
# Stone 48 proof: the parser joins the front end.
#
# selfhost/nifla-front.nifla — the toolchain front end written
# in Nifla, this stone carrying the lexer and the parser —
# must agree with the Swift front end (src/Lexer.swift and
# src/Parser.swift) byte for byte in `tree` mode: the same
# one-line parse tree on standard output, the same refusal on
# standard error, the same exit code, on every file of the
# corpus:
#
#   examples/, checker-examples/, floor-examples/,
#   voice-examples/, bare-examples/ (every .nifla)
#   selfhost/nifla-in-nifla.nifla and selfhost/nifla-front.nifla
#   tools/feathercheck.nifla
#   every fenced block in PRIMER.md and TUTORIAL.md whose info
#     string begins with "nifla" (extracted the way
#     run-primer.sh and run-tutorial.sh extract them)
#   the Cardnull OS 2 sources (~/workspace/cardnull-os-2/src,
#     read-only; a SKIP line is printed if the tree is absent)
#   front-examples/*.nifla — the Stone 47 lexer fixtures and
#     the Stone 48 parser fixtures (in tree mode the
#     lexer-refusal fixtures must agree on the lex error)
#
# The Swift side is spoken for by a proof-only oracle
# (tools/front-oracle.swift) that links the untouched
# src/Lexer.swift and src/Parser.swift and dumps trees in the
# identical format.
#
# The fixtures named in front-examples/BOUNDARY.txt are the
# verified-divergent boundary: in tree mode they diverge at
# the lex stage, and for each of them the two sides must
# DISAGREE. If one ever agrees, this proof fails — the
# boundary list is stale and must be revisited. Every other
# file must agree exactly.
#
# Prints PASS or FAIL per file and a summary with per-group
# counts.

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

# run_group <label> <files...> — compares the two tree dumps
# on every file; boundary fixtures (fixtures group only) must
# diverge instead.
GROUP_RESULTS=""
run_group() {
    label="$1"
    shift
    gpass=0
    gtotal=0
    for f in "$@"; do
        [ -f "$f" ] || continue
        gtotal=$((gtotal + 1))
        timeout 120 "$ORACLE" tree "$f" > "$SCRATCH/o.out" 2> "$SCRATCH/o.err"
        oc=$?
        timeout 120 "$FRONT" tree "$f" > "$SCRATCH/f.out" 2> "$SCRATCH/f.err"
        fc=$?
        agree=0
        if [ "$oc" -eq "$fc" ] && cmp -s "$SCRATCH/o.out" "$SCRATCH/f.out" && cmp -s "$SCRATCH/o.err" "$SCRATCH/f.err"; then
            agree=1
        fi
        if [ "$label" = "fixtures" ] && is_boundary "$f"; then
            if [ "$agree" -eq 1 ]; then
                echo "FAIL $f (named in BOUNDARY.txt but the two front ends AGREE in tree mode — the boundary list is stale and must be revisited)"
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

run_group examples examples/*.nifla
run_group checker checker-examples/*.nifla
run_group floor floor-examples/*.nifla
run_group voice voice-examples/*.nifla
run_group bare bare-examples/*.nifla
run_group selfhost selfhost/nifla-in-nifla.nifla selfhost/nifla-front.nifla
run_group tools tools/feathercheck.nifla
run_group primer "$SCRATCH"/primer/*.nifla
run_group tutorial "$SCRATCH"/tutorial/*.nifla

CARDNULL_DIR="$HOME/workspace/cardnull-os-2/src"
if [ -d "$CARDNULL_DIR" ]; then
    run_group cardnull "$CARDNULL_DIR"/*.nifla
else
    echo "SKIP cardnull (directory $CARDNULL_DIR is absent)"
    GROUP_RESULTS="$GROUP_RESULTS cardnull SKIPPED,"
fi

run_group fixtures front-examples/*.nifla

boundary_count=$(wc -l < "$BOUNDARY_LIST" | tr -d ' ')
echo "front-parser:$GROUP_RESULTS boundary $boundary_count noted"
if [ "$fail" -eq 0 ]; then
    echo "PASS front-parser (Stone 48: the Nifla-written parser's trees and refusals are byte-identical to the Swift parser's across the whole corpus, the boundary apart and verified divergent)"
else
    echo "FAIL front-parser: $fail failure(s)"
    exit 1
fi
