#!/bin/sh
# Stone 10 proofs: the grown-up voice — the error channel and
# the exit code. Ordinary examples are checked on standard
# output alone, but a program that speaks to the error channel
# or chooses its parting number has three channels to keep, so
# every program in voice-examples/ carries three expected
# files:
#
#   NAME.expected  what it says on standard output
#   NAME.err       what it says on standard error
#   NAME.code      the number it leaves behind (its exit code)
#
# Each program is run twice — once under ./nifla, once as a
# ./niflac-compiled program — and all three channels must match
# exactly both times: the same words on the screen, the same
# words on the error channel, the same parting number.
#
# Prints PASS or FAIL for each check, and a summary at the end.

set -u
cd "$(dirname "$0")"

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

# Runs one program and compares all three of its channels.
# $1 = the check's name; the rest is the command to run.
check_voice() {
    label=$1
    shift
    out=$(mktemp)
    err=$(mktemp)
    if $TIMEOUT "$@" >"$out" 2>"$err"; then
        status=0
    else
        status=$?
    fi
    wantcode=$(cat "voice-examples/$name.code")
    if [ "$status" -eq "$wantcode" ] \
       && diff -q "voice-examples/$name.expected" "$out" >/dev/null \
       && diff -q "voice-examples/$name.err" "$err" >/dev/null; then
        echo "PASS $label"
        pass=$((pass + 1))
    else
        echo "FAIL $label (expected exit $wantcode, got $status)"
        echo "--- expected stdout ---"
        cat "voice-examples/$name.expected"
        echo "--- actual stdout ---"
        cat "$out"
        echo "--- expected stderr ---"
        cat "voice-examples/$name.err"
        echo "--- actual stderr ---"
        cat "$err"
        fail=$((fail + 1))
    fi
    rm -f "$out" "$err"
}

for program in voice-examples/*.nifla; do
    name=$(basename "$program" .nifla)
    check_voice "$name (interpreted)" ./nifla "$program"
    bin="$WORK/voice-$name"
    cout=$(mktemp)
    cerr=$(mktemp)
    if $CTIMEOUT ./niflac "$program" -o "$bin" >"$cout" 2>"$cerr" && [ -x "$bin" ]; then
        check_voice "$name (compiled)" "$bin"
    else
        echo "FAIL $name (compiled; niflac would not compile it:)"
        cat "$cout" "$cerr"
        fail=$((fail + 1))
    fi
    rm -f "$cout" "$cerr"
done

echo "---"
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
