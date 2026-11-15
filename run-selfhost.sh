#!/bin/bash
# Nifla Stone 8 proof, kept current by Stone 10: the
# interpreter written in Nifla, compiled with niflac, runs the
# example suite — and its behavior must match the Swift
# interpreter's expected behavior on every channel: the words
# on standard output, the words on standard error, and whether
# it leaves in success or failure. No Swift interpreter is
# involved at run time: the only program running the examples
# is the compiled Nifla-written one.
#
# How each example is checked follows run_tests.sh's rules:
#   NAME.expected — the run must succeed (exit 0), say exactly
#     this on standard output, and nothing on standard error.
#   NAME.error — the run must fail (a nonzero exit), say
#     nothing on standard output, and say exactly this on
#     standard error.
# Stone 8 could only compare the words on standard output —
# Nifla had no error channel and no exit codes, so the
# self-host spoke an interpreted program's errors aloud and
# left with 0. Stone 10 gave the language sayerr, exitwith,
# and 'attempt'; the self-host uses all three now (and catches
# its own file failures, so an interpreted program's readfile
# failure is reported with the program's own line, as the
# Swift interpreter reports it), and this script compares all
# three channels.
#
# Two examples are NOT covered, honestly and by measurement:
#   endless — each call the interpreted program makes costs
#     several calls inside the self-host, so the host's own
#     five-hundred-call guard (interpreted host) or the real
#     processor stack (compiled host) gives out long before
#     the interpreted program's own guard can speak.
#   forever — each pass of the interpreted loop also spends
#     passes of the host's own loops, so the host's
#     million-pass guard speaks first, naming a line inside
#     nifla-in-nifla.nifla instead of the program's line 3.
cd "$(dirname "$0")"
./build.sh || exit 1

SH=./selfhost/nifla-in-nifla
echo "Compiling the self-hosted interpreter with niflac..."
rm -f "$SH" ./selfhost/nifla-in-nifla.swift
if ! timeout 600 ./niflac selfhost/nifla-in-nifla.nifla > /tmp/nifla-selfhost-build.txt 2>&1; then
    echo "FAIL: niflac could not compile the self-hosted interpreter:"
    cat /tmp/nifla-selfhost-build.txt
    exit 1
fi

pass=0
fail=0
total=0
rm -f stone6-note.txt
for f in examples/*.nifla; do
    name=$(basename "$f" .nifla)
    total=$((total + 1))
    if [ "$name" = "endless" ] || [ "$name" = "forever" ]; then
        echo "SKIP $name (not covered — see the note at the top of this script)"
        continue
    fi
    timeout 30 "$SH" "$f" > /tmp/nifla-selfhost-out.txt 2> /tmp/nifla-selfhost-err.txt
    status=$?
    if [ -f "examples/$name.error" ]; then
        if [ "$status" -ne 0 ] && [ ! -s /tmp/nifla-selfhost-out.txt ] \
           && diff -q "examples/$name.error" /tmp/nifla-selfhost-err.txt > /dev/null; then
            echo "PASS $name"
            pass=$((pass + 1))
        else
            echo "FAIL $name (expected a failure, silent stdout, and stderr matching examples/$name.error; got exit $status)"
            echo "--- expected stderr:"
            cat "examples/$name.error"
            echo "--- the self-host said (stdout):"
            cat /tmp/nifla-selfhost-out.txt
            echo "--- the self-host said (stderr):"
            cat /tmp/nifla-selfhost-err.txt
            fail=$((fail + 1))
        fi
    else
        if [ "$status" -eq 0 ] && [ ! -s /tmp/nifla-selfhost-err.txt ] \
           && diff -q "examples/$name.expected" /tmp/nifla-selfhost-out.txt > /dev/null; then
            echo "PASS $name"
            pass=$((pass + 1))
        else
            echo "FAIL $name (expected success, stderr empty, and stdout matching examples/$name.expected; got exit $status)"
            echo "--- expected stdout:"
            cat "examples/$name.expected"
            echo "--- the self-host said (stdout):"
            cat /tmp/nifla-selfhost-out.txt
            echo "--- the self-host said (stderr):"
            cat /tmp/nifla-selfhost-err.txt
            fail=$((fail + 1))
        fi
    fi
done
rm -f stone6-note.txt
echo "Self-hosted suite: $pass passed, $fail failed (of $total examples; endless and forever not covered)"
[ "$fail" -eq 0 ]
