#!/bin/bash
# Nifla Stone 8 proof: the interpreter written in Nifla,
# compiled with niflac, runs the example suite — and its
# output must match the Swift interpreter's expected output
# byte for byte. No Swift interpreter is involved at run time:
# the only program running the examples is the compiled
# Nifla-written one.
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
# Every other example — 31 of 33, including eight of the ten
# error examples — is covered, errors included: the self-host
# says an interpreted program's errors aloud (to stdout),
# where the Swift tools print them to stderr; the words
# themselves match byte for byte.
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
rm -f stone6-note.txt
for f in examples/*.nifla; do
    name=$(basename "$f" .nifla)
    if [ "$name" = "endless" ] || [ "$name" = "forever" ]; then
        echo "SKIP $name (not covered — see the note at the top of this script)"
        continue
    fi
    if [ -f "examples/$name.expected" ]; then
        want="examples/$name.expected"
    else
        want="examples/$name.error"
    fi
    timeout 30 "$SH" "$f" > /tmp/nifla-selfhost-out.txt 2> /tmp/nifla-selfhost-err.txt
    if diff -q "$want" /tmp/nifla-selfhost-out.txt > /dev/null && [ ! -s /tmp/nifla-selfhost-err.txt ]; then
        echo "PASS $name"
        pass=$((pass + 1))
    else
        echo "FAIL $name"
        echo "--- expected (from $want):"
        cat "$want"
        echo "--- the self-host said (stdout):"
        cat /tmp/nifla-selfhost-out.txt
        echo "--- the self-host said (stderr):"
        cat /tmp/nifla-selfhost-err.txt
        fail=$((fail + 1))
    fi
done
rm -f stone6-note.txt
echo "Self-hosted suite: $pass passed, $fail failed (of 33 examples; endless and forever not covered)"
