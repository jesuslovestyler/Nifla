#!/bin/sh
# Stone 5 proofs: the compiler and the checker.
#
# Part 1 — every program in examples/ is compiled with ./niflac
# into a scratch folder, and the compiled program must behave
# exactly as the interpreter's expected files say: the same words
# on standard output, the same plain-words error on standard
# error, the same success or failure. Three of the examples
# (broken, missing, badcall) are stopped by the checker before
# compiling; for those, niflac's refusal itself must be the
# expected error, with no program left behind.
#
# Part 2 — every program in checker-examples/ is a mistake the
# checker can prove before anything runs. Both ./nifla and
# ./niflac must refuse it: fail, say nothing on standard output,
# print exactly the expected plain-words error, and (for niflac)
# leave no program behind.
#
# Part 3 — one compiled program (examples/tyler.nifla) is copied
# alone into an empty folder and run there, with no interpreter
# and no other files, to prove it stands alone.
#
# Prints PASS or FAIL for each check, and a summary at the end.

set -u
cd "$(dirname "$0")"

# Safety nets: no single run may hang the proofs. Nifla's own
# guards should stop a bad program long before these.
TIMEOUT=""
CTIMEOUT=""
if command -v timeout >/dev/null 2>&1; then
    TIMEOUT="timeout 10"
    CTIMEOUT="timeout 120"
fi

./build.sh >/dev/null || { echo "BUILD FAILED"; exit 1; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

pass=0
fail=0
note_pass() { echo "PASS $1"; pass=$((pass + 1)); }
note_fail() { echo "FAIL $1"; fail=$((fail + 1)); }

# Runs a compiled program and compares its behavior with the
# example's expected files, the way run_tests.sh compares the
# interpreter's. $1 = example name, $2 = program to run.
check_behavior() {
    name=$1
    bin=$2
    out=$(mktemp)
    err=$(mktemp)
    if $TIMEOUT "$bin" >"$out" 2>"$err"; then
        status=0
    else
        status=$?
    fi
    if [ -f "examples/$name.error" ]; then
        if [ "$status" -ne 0 ] && [ ! -s "$out" ] && diff -q "examples/$name.error" "$err" >/dev/null; then
            note_pass "$name (compiled)"
        else
            note_fail "$name (compiled; expected a clean failure with this error:)"
            cat "examples/$name.error"
            echo "--- actual (exit $status) ---"
            cat "$out" "$err"
        fi
    else
        if [ "$status" -eq 0 ] && [ ! -s "$err" ] && diff -q "examples/$name.expected" "$out" >/dev/null; then
            note_pass "$name (compiled)"
        else
            note_fail "$name (compiled; expected:)"
            cat "examples/$name.expected"
            echo "--- actual (exit $status) ---"
            cat "$out" "$err"
        fi
    fi
    rm -f "$out" "$err"
}

echo "# Part 1 — the examples, compiled"
for program in examples/*.nifla; do
    name=$(basename "$program" .nifla)
    bin="$WORK/$name"
    cout=$(mktemp)
    cerr=$(mktemp)
    if $CTIMEOUT ./niflac "$program" -o "$bin" >"$cout" 2>"$cerr"; then
        compiled=0
    else
        compiled=$?
    fi
    if [ "$compiled" -ne 0 ] && [ -f "examples/$name.error" ]; then
        # Stopped by the checker before compiling: the refusal must
        # be exactly the expected error, said on standard error,
        # with nothing on standard output and no program left.
        if [ ! -s "$cout" ] && [ ! -e "$bin" ] && diff -q "examples/$name.error" "$cerr" >/dev/null; then
            note_pass "$name (checker refused before compiling)"
        else
            note_fail "$name (checker refusal did not match the expected error:)"
            cat "examples/$name.error"
            echo "--- actual (exit $compiled) ---"
            cat "$cout" "$cerr"
            [ -e "$bin" ] && echo "(a program was left behind)"
        fi
    elif [ "$compiled" -ne 0 ]; then
        note_fail "$name (niflac would not compile it:)"
        cat "$cerr"
    else
        check_behavior "$name" "$bin"
    fi
    rm -f "$cout" "$cerr"
done

echo "# Part 2 — the checker examples, refused by nifla and by niflac"
for program in checker-examples/*.nifla; do
    name=$(basename "$program" .nifla)
    for tool in nifla niflac; do
        out=$(mktemp)
        err=$(mktemp)
        bin="$WORK/check-$name"
        rm -f "$bin"
        if [ "$tool" = nifla ]; then
            if $TIMEOUT ./nifla "$program" >"$out" 2>"$err"; then status=0; else status=$?; fi
        else
            if $CTIMEOUT ./niflac "$program" -o "$bin" >"$out" 2>"$err"; then status=0; else status=$?; fi
        fi
        if [ "$status" -ne 0 ] && [ ! -s "$out" ] && diff -q "checker-examples/$name.error" "$err" >/dev/null \
           && { [ "$tool" = nifla ] || [ ! -e "$bin" ]; }; then
            note_pass "$name (checker, $tool refuses)"
        else
            note_fail "$name (checker, $tool should have refused with this error:)"
            cat "checker-examples/$name.error"
            echo "--- actual (exit $status) ---"
            cat "$out" "$err"
            [ "$tool" = niflac ] && [ -e "$bin" ] && echo "(a program was left behind)"
        fi
        rm -f "$out" "$err"
    done
done

echo "# Part 3 — a compiled program, standing alone"
alone="$WORK/alone"
mkdir -p "$alone"
if $CTIMEOUT ./niflac examples/tyler.nifla -o "$WORK/tyler-compiled" >/dev/null 2>&1 \
   && cp "$WORK/tyler-compiled" "$alone/tyler" \
   && [ "$(ls -A "$alone")" = "tyler" ]; then
    out=$(mktemp)
    err=$(mktemp)
    if (cd "$alone" && $TIMEOUT ./tyler >"$out" 2>"$err"); then status=0; else status=$?; fi
    if [ "$status" -eq 0 ] && [ ! -s "$err" ] && diff -q examples/tyler.expected "$out" >/dev/null; then
        note_pass "standalone (tyler runs alone in an empty folder)"
    else
        note_fail "standalone (tyler alone did not behave as expected; exit $status)"
        cat "$out" "$err"
    fi
    rm -f "$out" "$err"
else
    note_fail "standalone (could not set up the lone program)"
fi

echo "---"
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
