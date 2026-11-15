#!/bin/sh
# Run every example program in examples/ and check its output.
#
#   examples/NAME.nifla     the program
#   examples/NAME.expected  what it should say on standard output
#   examples/NAME.error     if this file exists instead, the program is
#                           expected to fail, and this is the plain-words
#                           error it should print (standard error)
#
# Prints PASS or FAIL for each example, and a summary at the end.

set -u
cd "$(dirname "$0")"

# A safety net: no example may run longer than ten seconds. Nifla's own
# runaway guard should stop a bad loop long before this — this is here
# so the test run itself can never hang.
TIMEOUT=""
if command -v timeout >/dev/null 2>&1; then
    TIMEOUT="timeout 10"
fi

./build.sh >/dev/null || { echo "BUILD FAILED"; exit 1; }

# The notefile example (Stone 6) writes this note while it runs;
# start and finish with it tidied away.
rm -f stone6-note.txt

pass=0
fail=0
for program in examples/*.nifla; do
    name=$(basename "$program" .nifla)
    out=$(mktemp)
    err=$(mktemp)
    if $TIMEOUT ./nifla "$program" >"$out" 2>"$err"; then
        status=0
    else
        status=$?
    fi

    if [ -f "examples/$name.error" ]; then
        # Error test: the run must fail, say nothing on stdout, and
        # print exactly the expected plain-words error.
        if [ "$status" -ne 0 ] && [ ! -s "$out" ] && diff -q "examples/$name.error" "$err" >/dev/null; then
            echo "PASS $name"
            pass=$((pass + 1))
        else
            echo "FAIL $name (expected a clean failure with this error:)"
            cat "examples/$name.error"
            echo "--- actual (exit $status) ---"
            cat "$out" "$err"
            fail=$((fail + 1))
        fi
    else
        if [ "$status" -eq 0 ] && [ ! -s "$err" ] && diff -q "examples/$name.expected" "$out" >/dev/null; then
            echo "PASS $name"
            pass=$((pass + 1))
        else
            echo "FAIL $name (expected:)"
            cat "examples/$name.expected"
            echo "--- actual (exit $status) ---"
            cat "$out" "$err"
            fail=$((fail + 1))
        fi
    fi
    rm -f "$out" "$err"
done

rm -f stone6-note.txt

echo "---"
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
