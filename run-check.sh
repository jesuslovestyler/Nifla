#!/bin/sh
# Stone 52 gate: the checker leg's single command.
#
# This script is the gate for the whole checker leg: it
# runs the corpus proof (Stones 50–51, as it stands —
# the checker stands whole in every mode: the hosted
# walk of Stone 50, and the bare and guest doors) and
# then the generated sweep (run-check-sweep.sh, Stone
# 52), stopping at the first failure, and on success
# prints one closing summary naming the whole claim.
#
# The corpus proof:
#
# selfhost/nifla-front.nifla — the toolchain front end
# written in Nifla, this stone carrying the checker beside
# the lexer and the parser — must agree with the Swift
# checker (src/Checker.swift) in its check modes: the same
# "checked" on standard output for an accepted program,
# the same refusal on standard error, the same exit code,
# on every file of the corpus:
#
#   hosted `check`: examples/, checker-examples/ (45 —
#     each must REFUSE, and the refusal must also equal
#     its .error file byte for byte), floor-examples/,
#     voice-examples/, selfhost (2), tools (1), every
#     fenced nifla block in PRIMER.md and TUTORIAL.md,
#     front-examples/*.nifla (104 fixtures — lex/parse
#     refusals agree through the front end, acceptances
#     then check), and check-examples/*.nifla (the Stone
#     50 checker fixtures and Stone 51's door/bare ones)
#   bare `check-bare`: bare-examples/, the Cardnull
#     OS 2 sources (read-only), and the door-/bare-
#     prefixed fixtures in check-examples/
#   guest `check-guest`: bare-examples/nifla-guest.nifla,
#     bare-examples/nifla-guest-desk.nifla, the
#     Cardnull feathers calculator-feather, paint-feather
#     and welcome-feather, and the same door-/bare-
#     prefixed fixtures
#
# The Swift side is spoken for by a proof-only oracle
# (tools/check-oracle.swift) that links the untouched
# src/Lexer.swift, src/Parser.swift, src/Interpreter.swift,
# src/BareCompiler.swift and src/Checker.swift — plus
# src/Compiler.swift and src/BareCompilerARM.swift, which
# the link pulls in (the bare compiler reaches
# findAssembler in Compiler.swift, and Compiler.swift
# reaches the ARM bare compiler).
#
# Stone 50's port ran the HOSTED walk in all three
# modes, and its proof carried a pending list of 22
# mode-and-file pairs that diverged only for the missing
# bare/guest tool doors and bare floor rules. Stone 51
# ports the doors and the floor rule whole: the pending
# list stands EMPTIED, and every file in the bare and
# guest groups must now agree byte for byte — this proof
# fails on ANY divergence in any group. The fixtures in
# front-examples/BOUNDARY.txt divide in two: the word
# fixtures (Stone 47) diverge at the lex stage in check
# mode, as in the front proofs, and must DISAGREE here
# too; the number fixtures (Stone 54, marked NUMBER
# BOUNDARY in that file) diverge in the VALUE of a
# number token — surfaced by the token dump, the tree
# dump and the generated Swift, and verified divergent
# there — while the check verdict AGREES here by the
# nature of the divergence (both sides accept; no
# verdict reads a value that finely), and this proof
# asserts that agreement for them by name, so a change
# on either side is caught either way.
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

# The number boundary's fixtures: the BOUNDARY.txt lines
# carrying the NUMBER BOUNDARY mark.
NUMBER_BOUNDARY_LIST="$SCRATCH/number-boundary.txt"
grep 'NUMBER BOUNDARY' front-examples/BOUNDARY.txt | awk '{print $1}' > "$NUMBER_BOUNDARY_LIST"

is_number_boundary() {
    grep -qx "$(basename "$1")" "$NUMBER_BOUNDARY_LIST"
}

pass=0
fail=0

# run_group <mode> <label> <files...> — compares the two
# check verdicts on every file; boundary fixtures (the
# fixtures group only) must diverge instead.
GROUP_RESULTS=""
run_group() {
    mode="$1"
    label="$2"
    shift 2
    gpass=0
    gtotal=0
    for f in "$@"; do
        [ -f "$f" ] || continue
        gtotal=$((gtotal + 1))
        timeout 120 "$ORACLE" "$mode" "$f" > "$SCRATCH/o.out" 2> "$SCRATCH/o.err"
        oc=$?
        timeout 120 "$FRONT" "$mode" "$f" > "$SCRATCH/f.out" 2> "$SCRATCH/f.err"
        fc=$?
        agree=0
        if [ "$oc" -eq "$fc" ] && cmp -s "$SCRATCH/o.out" "$SCRATCH/f.out" && cmp -s "$SCRATCH/o.err" "$SCRATCH/f.err"; then
            agree=1
        fi
        if [ "$label" = "fixtures" ] && is_boundary "$f"; then
            if is_number_boundary "$f"; then
                # The number boundary: the divergence is in
                # a number's value, which no check verdict
                # reads — the two sides must AGREE here,
                # both accepting, and the agreement is the
                # assertion (the divergence itself is
                # verified in tokens, tree and compile).
                if [ "$agree" -eq 1 ] && [ "$oc" -eq 0 ]; then
                    echo "BOUNDARY $f (number boundary: the check verdicts agree, both accepting, as the record states)"
                    gpass=$((gpass + 1))
                else
                    echo "FAIL $f (a NUMBER BOUNDARY fixture must be ACCEPTED identically in check mode — the record is stale and must be revisited)"
                    fail=$((fail + 1))
                fi
                continue
            fi
            if [ "$agree" -eq 1 ]; then
                echo "FAIL $f (named in BOUNDARY.txt but the two sides AGREE in check mode — the boundary list is stale and must be revisited)"
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

run_group check examples examples/*.nifla
run_group check checker checker-examples/*.nifla
run_group check floor floor-examples/*.nifla
run_group check voice voice-examples/*.nifla
run_group check selfhost selfhost/nifla-in-nifla.nifla selfhost/nifla-front.nifla
run_group check tools tools/feathercheck.nifla
run_group check primer "$SCRATCH"/primer/*.nifla
run_group check tutorial "$SCRATCH"/tutorial/*.nifla
run_group check fixtures front-examples/*.nifla
run_group check checkfix check-examples/*.nifla
run_group check-bare checkfixbare check-examples/door-*.nifla check-examples/bare-*.nifla
run_group check-guest checkfixguest check-examples/door-*.nifla check-examples/bare-*.nifla

run_group check-bare bare bare-examples/*.nifla

CARDNULL_DIR="$HOME/workspace/cardnull-os-2/src"
if [ -d "$CARDNULL_DIR" ]; then
    run_group check-bare cardnull "$CARDNULL_DIR"/*.nifla
    run_group check-guest guestbare bare-examples/nifla-guest.nifla bare-examples/nifla-guest-desk.nifla
    run_group check-guest guestcard "$CARDNULL_DIR/calculator-feather.nifla" "$CARDNULL_DIR/paint-feather.nifla" "$CARDNULL_DIR/welcome-feather.nifla"
else
    echo "SKIP cardnull (directory $CARDNULL_DIR is absent)"
    GROUP_RESULTS="$GROUP_RESULTS cardnull SKIPPED, guestcard SKIPPED,"
    run_group check-guest guestbare bare-examples/nifla-guest.nifla bare-examples/nifla-guest-desk.nifla
fi

boundary_count=$(wc -l < "$BOUNDARY_LIST" | tr -d ' ')
echo "check:$GROUP_RESULTS boundary $boundary_count noted, Stone 50 pending list emptied (0 pending)"
if [ "$fail" -eq 0 ]; then
    echo "PASS check (Stone 51: the Nifla-written checker's verdicts are byte-identical to the Swift checker's across the whole corpus in all three modes — hosted, bare and guest — the boundary apart and verified divergent; the Stone 50 pending list stands emptied, all 22 of its pairs now agreeing byte for byte)"
else
    echo "FAIL check: $fail failure(s)"
    exit 1
fi

# Stone 52: the generated sweep, after the corpus proof.
# The gate stops at the first failure.
./run-check-sweep.sh || { echo "FAIL check-gate: the generated sweep failed — the gate stops here"; exit 1; }

echo "PASS check-gate (Stone 52: the Nifla-written checker is byte-identical to the Swift checker in all three modes — check, check-bare and check-guest — across the whole corpus:$GROUP_RESULTS and the 64 fixtures in check-examples/, and across the generated sweep of 300 verdict programs, 200 door-soup programs in each of the bare and guest modes, and 250 number-heavy programs, boundary $boundary_count noted)"
